type DocumentData = Record<string, unknown>;

type Reference = {
  path: string;
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

class Transaction {
  private hasWritten = false;

  public constructor(
    private readonly documents: Map<string, DocumentData>,
    private readonly trace: TransactionTrace,
  ) {}

  public async get(reference: Reference): Promise<Snapshot> {
    if (this.hasWritten) {
      throw new Error("Firestore transactions require all reads to be executed before all writes.");
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
}

/**
 * A deliberately small Firestore transaction double for handler tests. It is
 * not a rules substitute; the emulator suite covers authorization separately.
 */
export class InMemoryFirestore {
  private readonly documents = new Map<string, DocumentData>();
  private readonly traces: TransactionTrace[] = [];

  public collection(collectionPath: string): { doc(id: string): Reference } {
    return {
      doc: (id: string): Reference => ({ path: `${collectionPath}/${id}` }),
    };
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
}
