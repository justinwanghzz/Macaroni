/* Source navigation stays separate from Markdown/PDF rendering; all positions are zero-based. */
(() => {
  let revision = 0;
  let activeLine = 0;
  const preview = () => document.getElementById('preview');
  const exporting = () => document.body.classList.contains('exporting');
  const blocks = () => [...preview().querySelectorAll('[data-source-start]')];
  const start = el => Number(el.dataset.sourceStart);
  const end = el => Number(el.dataset.sourceEnd);

  window.installSourceMaps = md => {
    md.core.ruler.push('utility_source_lines', state => {
      const raw=state.src.split('\n');
      for (const token of state.tokens) {
        if (!token.map || !token.block || token.nesting === -1) continue;
        token.attrSet('data-source-start', String(token.map[0]));
        token.attrSet('data-source-end', String(token.map[1]));
        if (token.type === 'fence' || token.type === 'code_block') {
          const contentStart = token.map[0] + (token.type === 'fence' ? 1 : 0);
          const count = token.content.replace(/\n$/, '').split('\n').length;
          token.attrSet('data-source-code', 'true');
          token.attrSet('data-content-start', String(contentStart));
          token.attrSet('data-content-end', String(contentStart + count));
          const content=token.content.replace(/\n$/, '').split('\n');
          const prefixes=content.map((line,i)=>{const source=raw[contentStart+i] || '';return source.endsWith(line) ? source.length-line.length : 0;});
          token.attrSet('data-source-prefixes',JSON.stringify(prefixes));
        }
      }
    });
    for (const type of ['fence','code_block']) {
      const original = md.renderer.rules[type];
      md.renderer.rules[type] = (tokens,index,options,env,renderer) => {
        const token=tokens[index];
        const attrs=(token.attrs || []).filter(([name]) => name.startsWith('data-source-') || name.startsWith('data-content-')).map(([name,value]) => ` ${name}="${value}"`).join('');
        return original(tokens,index,options,env,renderer).replace(/^<pre>/,`<pre${attrs}>`);
      };
    }
    return md;
  };

  window.setSourceRevision = value => {revision = value;};
  window.prepareSourcePreview = () => {
    // markdown-it puts fence attributes on <code>; keep just the outer <pre> navigable.
    for (const code of preview().querySelectorAll('pre > code')) {
      for (const attr of [...code.attributes]) if (attr.name.startsWith('data-source-') || attr.name.startsWith('data-content-')) code.removeAttribute(attr.name);
    }
  };
  function targetFor(line) {
    const all = blocks();
    // Prefer the smallest, deepest range: list items / table rows over their containers.
    const candidates = all.filter(el => start(el) <= line && line < end(el));
    candidates.sort((a,b) => (end(a)-start(a))-(end(b)-start(b)) || (a.contains(b) ? 1 : b.contains(a) ? -1 : 0));
    if (candidates.length) return candidates[0];
    // Blank lines, closing syntax and EOF use the nearest preceding block.
    return all.filter(el => start(el) <= line).sort((a,b) => start(b)-start(a) || (end(a)-start(a))-(end(b)-start(b)))[0] || all[0] || null;
  }
  window.revealSourceLine = (line, expectedRevision, force = false) => {
    if (exporting() || expectedRevision !== revision || !Number.isInteger(line) || line < 0) return null;
    activeLine = line;
    const target = targetFor(line);
    if (!target) return null;
    const previous = preview().querySelector('.source-active');
    if (previous !== target) {previous?.classList.remove('source-active');target.classList.add('source-active');}
    const rect = target.getBoundingClientRect();
    let y = rect.top;
    if (target.dataset.sourceCode === 'true') {
      const first = Number(target.dataset.contentStart), last = Number(target.dataset.contentEnd);
      const fraction = Math.max(0,Math.min(1,(line-first+0.5)/Math.max(1,last-first)));
      y += 14 + fraction*Math.max(0,rect.height-28);
    }
    // Typing within an already visible block does not repeatedly drag the preview around.
    const bottom = target.dataset.sourceCode === 'true' ? y+24 : Math.min(rect.bottom,y+80);
    if (force || y < 36 || bottom > window.innerHeight-36) window.scrollTo({top:Math.max(0,window.scrollY+y-window.innerHeight*0.3),behavior:'auto'});
    return {start:start(target),end:end(target),line};
  };
  window.sourceNavigationState = () => ({revision,line:activeLine,start:preview().querySelector('.source-active') ? start(preview().querySelector('.source-active')) : null});

  preview().addEventListener('click', event => {
    if (exporting() || event.button !== 0 || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
    const node = event.target instanceof Element ? event.target : event.target.parentElement;
    // Preserve external link handling, text selection and copying from the preview.
    if (node.closest('a[href]') || !window.getSelection().isCollapsed) return;
    const block = node.closest('[data-source-start]');
    if (!block || !preview().contains(block)) return;
    let line = start(block), column = 0;
    if (block.dataset.sourceCode === 'true') {
      const code = block.querySelector('code');
      let caret = document.caretRangeFromPoint?.(event.clientX,event.clientY);
      if (!caret && document.caretPositionFromPoint) {
        const position = document.caretPositionFromPoint(event.clientX,event.clientY);
        if (position) {caret=document.createRange();caret.setStart(position.offsetNode,position.offset);caret.collapse(true);}
      }
      if (code && caret && code.contains(caret.startContainer)) {
        const range = document.createRange();range.selectNodeContents(code);range.setEnd(caret.startContainer,caret.startOffset);
        const before = range.toString(), rows = before.split('\n');
        line = Math.min(Number(block.dataset.contentEnd)-1,Number(block.dataset.contentStart)+rows.length-1);
        column = rows[rows.length-1].length + (JSON.parse(block.dataset.sourcePrefixes || '[]')[line-Number(block.dataset.contentStart)] || 0);
      } else {line = Number(block.dataset.contentStart);}
    }
    preview().querySelector('.source-active')?.classList.remove('source-active');block.classList.add('source-active');activeLine=line;
    window.webkit?.messageHandlers?.sourceNavigation?.postMessage({line,column,revision});
  });
})();
