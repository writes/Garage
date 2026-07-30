type DocumentData = Record<string, unknown>;

type Reference = {
  path: string;
};

type QueryFilter = {
  fieldPath: string;
  opStr: string;
  value: unknown;
};

export type TransactionTrace = {
  reads: string[];
  writes: string[];
};

class Snapshot {
  public constructor(private readonly value: DocumentData | undefined) {}

  public get exists(): boolean {
    return this.value !== undefined;
  }

  public data(): DocumentData | undefined {
    return this.value === undefined ? undefined : structuredClone(this.value);
  }
}

class QueryDocumentSnapshot {
  public constructor(
    public readonly ref: Reference,
    private readonly value: DocumentData,
  ) {}

  public data(): DocumentData {
    return structuredClone(this.value);
  }
}

class QuerySnapshot {
  public constructor(public readonly docs: QueryDocumentSnapshot[]) {}
}

class Query {
  public constructor(
    protected readonly documents: Map<string, DocumentData>,
    private readonly collectionPath: string,
    private readonly filters: QueryFilter[] = [],
    private readonly take?: number,
  ) {}

  public where(fieldPath: string, opStr: string, value: unknown): Query {
    return new Query(this.documents, this.collectionPath, [...this.filters, { fieldPath, opStr, value }], this.take);
  }

  public limit(take: number): Query {
    return new Query(this.documents, this.collectionPath, this.filters, take);
  }

  public tracePath(): string {
    return `${this.collectionPath}?${this.filters.map((filter) => `${filter.fieldPath}${filter.opStr}`).join("&")}`;
  }

  public snapshot(): QuerySnapshot {
    const prefix = `${this.collectionPath}/`;
    const docs = [...this.documents.entries()]
      .filter(([path]) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
      .filter(([, data]) => this.filters.every((filter) => {
        const value = data[filter.fieldPath];
        if (filter.opStr === "==") return value === filter.value;
        if (filter.opStr === "<") return typeof value === "number" && typeof filter.value === "number" && value < filter.value;
        throw new Error(`Unsupported in-memory query operator: ${filter.opStr}`);
      }))
      .map(([path, data]) => new QueryDocumentSnapshot({ path }, data));
    return new QuerySnapshot(this.take === undefined ? docs : docs.slice(0, this.take));
  }
}

class CollectionReference extends Query {
  public constructor(documents: Map<string, DocumentData>, private readonly collectionPath: string) {
    super(documents, collectionPath);
  }

  public doc(id: string): Reference {
    return { path: `${this.collectionPath}/${id}` };
  }
}

class Transaction {
  private hasWritten = false;

  public constructor(
    private readonly documents: Map<string, DocumentData>,
    private readonly trace: TransactionTrace,
  ) {}

  public async get(reference: Reference): Promise<Snapshot>;
  public async get(query: Query): Promise<QuerySnapshot>;
  public async get(reference: Reference | Query): Promise<Snapshot | QuerySnapshot> {
    if (this.hasWritten) {
      throw new Error("Firestore transactions require all reads to be executed before all writes.");
    }

    if (reference instanceof Query) {
      this.trace.reads.push(reference.tracePath());
      return reference.snapshot();
    }

    this.trace.reads.push(reference.path);
    return new Snapshot(this.documents.get(reference.path));
  }

  public set(reference: Reference, data: DocumentData, options?: { merge?: boolean }): this {
    this.hasWritten = true;
    this.trace.writes.push(reference.path);
    const existing = this.documents.get(reference.path);
    const nextValue = options?.merge && existing ? { ...existing, ...structuredClone(data) } : structuredClone(data);
    this.documents.set(reference.path, nextValue);
    return this;
  }

  public create(reference: Reference, data: DocumentData): this {
    this.hasWritten = true;
    this.trace.writes.push(reference.path);
    if (this.documents.has(reference.path)) {
      throw new Error(`Document already exists: ${reference.path}`);
    }
    this.documents.set(reference.path, structuredClone(data));
    return this;
  }
}

/**
 * A deliberately small Firestore transaction double for handler tests. It is
 * not a rules substitute; the emulator suite covers authorization separately.
 */
export class InMemoryFirestore {
  private readonly documents = new Map<string, DocumentData>();
  private readonly traces: TransactionTrace[] = [];

  public collection(collectionPath: string): CollectionReference {
    return new CollectionReference(this.documents, collectionPath);
  }

  public async runTransaction<T>(updateFunction: (transaction: Transaction) => Promise<T>): Promise<T> {
    const trace: TransactionTrace = { reads: [], writes: [] };
    this.traces.push(trace);
    return updateFunction(new Transaction(this.documents, trace));
  }

  public seed(path: string, data: DocumentData): void {
    this.documents.set(path, structuredClone(data));
  }

  public data(path: string): DocumentData | undefined {
    const value = this.documents.get(path);
    return value === undefined ? undefined : structuredClone(value);
  }

  public transactionTraces(): TransactionTrace[] {
    return structuredClone(this.traces);
  }

  public collectionData(collectionPath: string): Array<{ id: string; data: DocumentData }> {
    const prefix = `${collectionPath}/`;
    return [...this.documents.entries()]
      .filter(([path]) => path.startsWith(prefix) && !path.slice(prefix.length).includes("/"))
      .map(([path, data]) => ({ id: path.slice(prefix.length), data: structuredClone(data) }));
  }
}
