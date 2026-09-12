"""Keep internal attachment references out of user-visible Markdown."""

from markdown_it import MarkdownIt
from markdown_it.rules_inline import image, link


def _reference_rule(rule):
    def parse(state, silent):
        start, count = state.pos, len(state.tokens)
        matched = rule(state, silent)
        if matched and not silent and len(state.tokens) > count:
            kind = "image" if rule is image else "link_open"
            token = next((value for value in state.tokens[count:] if value.type == kind), None)
            if token is not None:
                destination = token.attrGet("src") or token.attrGet("href") or ""
                if destination.lower().startswith("galaxyssi-artifact://"):
                    token.meta["internal_reference_span"] = (start, state.pos)
        return matched
    return parse


def strip_internal_artifact_links(content: str) -> str:
    source = str(content or "")
    if "galaxyssi-artifact://" not in source.lower():
        return source
    parser = MarkdownIt("commonmark")
    parser.inline.ruler.at("image", _reference_rule(image))
    parser.inline.ruler.at("link", _reference_rule(link))
    offsets = [0]
    for line in source.splitlines(keepends=True):
        offsets.append(offsets[-1] + len(line))
    spans = []
    for block in parser.parse(source):
        if block.type != "inline" or not block.map:
            continue
        start, end = offsets[block.map[0]], offsets[block.map[1]]
        # Inline offsets exclude Markdown list/quote prefixes; map back to source characters.
        positions, cursor = [], start
        for line in block.content.splitlines(keepends=True):
            value = line.rstrip("\n")
            at = source.find(value, cursor, end)
            if at < 0:
                positions = []
                break
            positions.extend(range(at, at + len(value)))
            cursor = at + len(value)
            if line.endswith("\n"):
                newline = source.find("\n", cursor, end)
                if newline < 0:
                    positions = []
                    break
                positions.append(newline)
                cursor = newline + 1
        for token in block.children or []:
            span = token.meta.get("internal_reference_span")
            if span and positions and span[1] <= len(positions):
                spans.append((positions[span[0]], positions[span[1] - 1] + 1))
    cursor, result = 0, []
    for start, end in sorted(set(spans)):
        if start >= cursor:
            result.append(source[cursor:start])
            cursor = end
    result.append(source[cursor:])
    return "".join(result)
