#!/usr/bin/env python3
"""Generate redistributable demo inputs. Requires Pillow; no network access."""
from pathlib import Path
import random, zipfile
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parent.parent / 'Fixtures'
root.mkdir(exist_ok=True)
r = random.Random(42)
im = Image.new('RGB', (1800, 1200))
p = im.load()
for y in range(im.height):
    for x in range(im.width):
        p[x,y] = (int(x/1800*220)+r.randrange(30),int(y/1200*220)+r.randrange(30),80+r.randrange(100))
d = ImageDraw.Draw(im); d.rectangle((100,100,900,300),fill='white'); d.text((150,180),'UTILITY / Image preparation demo',fill='black',font_size=40)
im.save(root/'Large-photo.jpg', quality=98)
alpha = Image.new('RGBA',(800,500),(0,0,0,0)); d = ImageDraw.Draw(alpha); d.rounded_rectangle((70,70,730,430),radius=50,fill=(45,110,230,200)); alpha.save(root/'Transparent.png')
(root/'Notes.md').write_text('# Quick edits\n\nA lightweight editor with a live preview.\n\n- Markdown\n- **Formatting**\n- Local math rendering\n\n$$\\sum_{k=1}^n k=\\frac{n(n+1)}{2}$$\n\n```swift\nlet tools = ["shelf", "convert", "preview"]\n```\n')
files = {'word/document.xml': '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Utility demo document</w:t></w:r></w:p><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Prepare documents locally for your coding agent.</w:t></w:r></w:p></w:body></w:document>', '[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>', '_rels/.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'}
with zipfile.ZipFile(root/'Brief.docx','w',zipfile.ZIP_DEFLATED) as z:
    for k,v in files.items(): z.writestr(k,v)
print(root)
