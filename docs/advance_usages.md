# Advance Usages


## Operate AST

Proc `markdown` supports an additional `root=` argument.
By default, it's `Document()`. You can set a new root for further operating.
For example,

```nim
let root = Document()
discard markdown("# Hello World\nTest.", root=root)
```

After calling `markdown()`, `root` is a fully parsed abstracted syntax tree.
You can add some new nodes to it.
For example,

```nim
let p = Paragraph(loose: true)
let em = Em()
let text = Text(doc: "emphasis text.")
em.appendChild(text)
p.appendChild(em)
root.appendChild(p)
```

You can render the modified root by calling `render()`:

```nim
render(root)
```

It'll render a new paragraph as expected:

```html
<h1>Hello World</h1>
<p>Test.</p>
<p><em>emphasis text.</em></p>
```
