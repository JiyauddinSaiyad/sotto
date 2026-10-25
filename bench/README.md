# Benchmarks

Reproduce the numbers on the site. Needs Xcode and Apple Intelligence turned on.

```sh
# Language model: speed on a few realistic prompts
find LibriSpeech/test-clean -name "*.trans.txt" | sort | xargs cat | cut -d' ' -f2- > corpus.txt
swiftc -O bench/llm.swift -o build/llm-bench && build/llm-bench corpus.txt

# Speech to text: LibriSpeech test-clean (https://www.openslr.org/12)
swiftc -O bench/asr.swift -o build/asr-bench
build/asr-bench LibriSpeech/test-clean > build/asr.tsv
python3 bench/wer.py build/asr.tsv LibriSpeech/test-clean
```

Let the Mac cool down between runs. A fanless Air throttles, and you'll measure the heat instead of the model.
