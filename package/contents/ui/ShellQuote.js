.pragma library

// sessionId/directory reach a real shell via TerminalHost.sendInput — quote them
// like a shell would (single-quote, escape embedded single quotes).
function shellQuote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'";
}
