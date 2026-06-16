"""Helpers for reading generated Lua quoted string literals."""


def unescape_lua_string(s):
    out = []
    pending = bytearray()
    i = 0

    def flush_bytes():
        if pending:
            out.append(pending.decode("utf-8", "replace"))
            pending.clear()

    while i < len(s):
        ch = s[i]
        if ch != "\\":
            flush_bytes()
            out.append(ch)
            i += 1
            continue

        i += 1
        if i >= len(s):
            flush_bytes()
            out.append("\\")
            break

        esc = s[i]
        if esc.isdigit():
            digits = esc
            i += 1
            while i < len(s) and len(digits) < 3 and s[i].isdigit():
                digits += s[i]
                i += 1
            pending.append(int(digits, 10) % 256)
            continue

        flush_bytes()
        if esc == "n":
            out.append("\n")
        elif esc == "r":
            out.append("\r")
        elif esc == "t":
            out.append("\t")
        elif esc in {'"', "'", "\\"}:
            out.append(esc)
        else:
            out.append(esc)
        i += 1

    flush_bytes()
    return "".join(out)
