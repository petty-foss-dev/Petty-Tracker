package com.isaaclamb.pettytracker.domain

import java.net.URI

/**
 * Accepts "example.com/item" as well as full links. Returns "" for blank input and null when the text
 * can't be a web address.
 */
fun normalizeProductUrl(text: String): String? {
    val trimmed = text.trim()
    if (trimmed.isEmpty()) return ""
    val candidate = if ("://" in trimmed) trimmed else "https://$trimmed"
    val uri = runCatching { URI(candidate) }.getOrNull() ?: return null
    return candidate.takeIf { uri.scheme?.lowercase() in setOf("http", "https") && !uri.host.isNullOrEmpty() }
}
