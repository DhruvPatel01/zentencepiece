import sentencepiece
model = sentencepiece.SentencePieceProcessor(model_file="./models/gemma3-27b-it.model")

txt = "<start_of_turn> Hello World! How are you doing! - ધ્રુવ"
txt = """The Sanahin Bridge (Armenian: Սանահինի or Սանահնի կամուրջ, Sanahini or Sanahni kamurj)[6] is a medieval stone arch bridge spanning the Debed River in Alaverdi in the northern Armenian province of Lori. Built in the late 12th century, it is considered one of the most remarkable bridges of medieval Armenia. Though largely intact, it has undergone multiple restorations since the late 19th century. Until the 1960s, the bridge was used for motor transport, but it has since been converted into a pedestrian-only walkway.

It is a UNESCO World Heritage Site along with Sanahin Monastery, to which it has close links, and the nearby Haghpat Monastery.[7] A historic landmark of Lori[8] and a symbol of Alaverdi, it is featured on the town's coat of arms.[9] Locally, it is often referred to as simply "The Stone Bridge" (K’are kamurjë).[10][11] "
"""
print(len(txt))
for i in range(10000):
    model.encode(txt)
