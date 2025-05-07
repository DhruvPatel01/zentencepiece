import zentencepiece
model = zentencepiece.load("models/gemma3-27b-it.model")
import sys

with open(sys.argv[1]) as f:
    txt = f.read().strip()

model.tokenize(txt)
