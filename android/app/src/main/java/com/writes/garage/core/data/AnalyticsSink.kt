package com.writes.garage.core.data

interface AnalyticsSink {
    fun log(event: String, params: Map<String, Any?> = emptyMap())

    fun setEnabled(enabled: Boolean)
}

/** Drops everything (default until the user opts in). */
object NoopAnalyticsSink : AnalyticsSink {
    override fun log(event: String, params: Map<String, Any?>) = Unit

    override fun setEnabled(enabled: Boolean) = Unit
}
