# Word error rate against LibriSpeech references. Plain Levenshtein over words, no tricks.
# Usage: python3 bench/wer.py build/asr.tsv path/to/LibriSpeech/test-clean
import pathlib, re, sys

ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()

def say(n):  # LibriSpeech spells numbers out; the recognizer writes digits. Meet in the middle.
    if n < 20: return ONES[n]
    if n < 100: return TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
    if n < 1000: return ONES[n // 100] + " hundred" + ("" if n % 100 == 0 else " " + say(n % 100))
    if 1100 <= n < 2000:  # years: 1847 -> eighteen forty seven, 1900 -> nineteen hundred
        return say(n // 100) + (" hundred" if n % 100 == 0 else " " + say(n % 100))
    return say(n // 1000) + " thousand" + ("" if n % 1000 == 0 else " " + say(n % 1000))

def norm(s):
    s = s.lower().replace("-", " ").replace("’", "'")
    s = re.sub(r"\d+", lambda m: " " + say(int(m.group())) + " " if int(m.group()) < 1_000_000 else m.group(), s)
    s = re.sub(r"[^a-z' ]", " ", s)
    return [w.strip("'") for w in s.split() if w.strip("'")]

def edits(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        prev, row[0] = row[0], i
        for j, y in enumerate(b, 1):
            prev, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, prev + (x != y))
    return row[-1]

refs = {}
for f in pathlib.Path(sys.argv[2]).rglob("*.trans.txt"):
    for line in f.read_text().splitlines():
        k, v = line.split(" ", 1)
        refs[k] = v

errs = words = n = 0
for line in open(sys.argv[1]):
    k, _, hyp = line.rstrip("\n").partition("\t")
    if k not in refs: continue  # partial download: audio landed, its transcript didn't
    n += 1
    r = norm(refs[k])
    errs += edits(r, norm(hyp))
    words += len(r)
print(f"utterances {n}  words {words}  WER {100 * errs / words:.2f}%")
