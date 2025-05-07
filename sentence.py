import sentencepiece as sp
model= sp.SentencePieceProcessor(model_file="./models/gemma3-27b-it.model")
txt = "<start_of_turn> Hello World! How are you doing! - ધ્રુવ"
for i in range(100000):
    model.tokenize(txt)
