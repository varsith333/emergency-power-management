import sys

def strip_comments(text):
    out = []
    i, n = 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == '\\' and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
                if text[i] == '\n':
                    out.append('\n')
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)

def tidy(text):
    lines = [l.rstrip() for l in text.split('\n')]
    res, blank = [], False
    for l in lines:
        if l.strip() == '':
            if blank:
                continue
            blank = True
            res.append('')
        else:
            blank = False
            res.append(l)
    while res and res[0] == '':
        res.pop(0)
    while res and res[-1] == '':
        res.pop()
    return '\n'.join(res) + '\n'

for path in sys.argv[1:]:
    with open(path, 'r', newline='') as f:
        src = f.read()
    clean = tidy(strip_comments(src))
    with open(path, 'w', newline='') as f:
        f.write(clean)
    print('%-16s -> %d lines' % (path.split('\\')[-1], clean.count('\n')))
