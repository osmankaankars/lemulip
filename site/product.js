"use strict";
// The sample state is local. This page never reads, uploads, or converts user files.
(() => {
  const $ = id => document.getElementById(id);
  const data = window.LEMULIP_CATALOG;
  if (!data || !$('desktop-demo')) return;
  const esc = text => String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const desktop = $('desktop-demo'), grid = $('sample-grid'), svg = $('wheel-svg');
  let source = $('sample-file');
  const sampleFiles = [...grid.querySelectorAll('[data-sample]')];
  let sampleIndex = 0, mode = 'convert', step = 0, wheelPage = 0, selected = 0;
  let autoplay = !reduced.matches, visible = true, timer = null, pointer = null, suppressClick = false;
  const sample = () => data.samples[sampleIndex];
  const stem = name => name.replace(/\.[^.]+$/, '');
  const announce = text => { $('announcer').textContent = text; };
  const nativeNotes = {
    images:[['Built In','PNG, JPG, HEIC, TIFF, BMP And PDF.'],['Included','ImageMagick For WebP And AVIF.']],
    pdf:[['Built In','PDF Tools And Offline OCR.'],['Text','Selectable Text Or OCR Required.']],
    audio:[['Built In','M4A, WAV And AIFF Where Codecs Allow.'],['Included','FFmpeg For Other Targets.']],
    video:[['Built In','MP4, MOV And M4A Where Codecs Allow.'],['Included','FFmpeg For Other Targets.']],
    documents:[['Built In','Basic Markdown, TXT And Basic RTF To DOCX.'],['Optional','LibreOffice Or Pandoc For Richer Documents.']],
    spreadsheets:[['Built In','CSV / TSV To XLSX. CSV And TSV Interchange.'],['Optional','LibreOffice For Other Workbook Routes.']],
    presentations:[['Optional','LibreOffice For Presentation Conversions.']],
    subtitles:[['Built In','SRT And VTT Interchange. Plain Text Export.']],
    archives:[['Create','ZIP, TAR And GZIP.'],['Extract','Supported Archives Into A New Folder.']]
  };
  const renderNotes = notes => notes.map(([label,text]) => '<div class="engine-note"><strong>'+esc(label)+'</strong>'+text.split(/\. (?=[A-Z])/).map(part=>'<p>'+esc(part.endsWith('.')?part:part+'.')+'</p>').join('')+'</div>').join('');
  const engineFor = ext => {
    const id = sample().id;
    if (id === 'images' && ['webp','avif'].includes(ext)) return 'ImageMagick';
    if (id === 'audio' && !['m4a','wav','aiff'].includes(ext)) return 'FFmpeg';
    if (id === 'video' && !['mp4','mov','m4a'].includes(ext)) return 'FFmpeg';
    if (id === 'presentations') return 'LibreOffice';
    if (id === 'spreadsheets' && !['csv','tsv','xlsx'].includes(ext)) return 'LibreOffice';
    if (id === 'documents' && ['epub','html','odt'].includes(ext)) return 'Pandoc';
    return null;
  };
  function operations() {
    if (mode === 'actions') return data.actions;
    if (mode === 'tools') return sample().tools;
    if (sample().id === 'archives') return sample().tools;
    const input = sample().name.split('.').pop();
    return sample().formats.filter(x => x !== input).map(ext => ({id:'convert.'+ext,title:ext.toUpperCase(),extension:ext,engine:engineFor(ext)}));
  }
  function stopTour() { autoplay = false; clearTimeout(timer); updatePlay(); }
  function updatePlay() {
    $('tour-toggle').textContent = autoplay ? 'Ⅱ' : '▶';
    $('tour-toggle').setAttribute('aria-label', autoplay ? 'Pause Tour' : 'Play Tour');
    $('tour-toggle').title = autoplay ? 'Pause Tour' : 'Play Tour';
    $('tour-toggle').setAttribute('aria-pressed', String(autoplay));
    desktop.dataset.autoplay = String(autoplay);
  }
  function schedule() {
    clearTimeout(timer);
    if (autoplay && visible && !document.hidden) timer = setTimeout(() => {
      if (step === 3) { sampleIndex = (sampleIndex+1)%data.samples.length; setSample(); }
      else setStep(step+1);
      schedule();
    }, step === 3 ? 2600 : step === 2 ? 2100 : 1700);
  }
  function setSample() {
    source.removeAttribute('id');
    source = sampleFiles[sampleIndex]; source.id = 'sample-file';
    sampleFiles.forEach((button,i) => {
      button.setAttribute('aria-pressed',String(i===sampleIndex));
      button.classList.remove('picked');
      button.setAttribute('aria-label','Pick Up '+data.samples[i].name);
    });
    mode = 'convert'; wheelPage = 0; selected = 0;
    updateModes(); setStep(0);
  }
  function updateModes() {
    document.querySelectorAll('[data-mode]').forEach(b => b.setAttribute('aria-pressed',String(b.dataset.mode === mode)));
  }
  const captions = ['Drag a file, or click it to begin.','Tap Shift for formats. The wheel comes to your drag.','Drop onto a segment, or click an operation.','A new sample copy, beside the original.'];
  function setStep(value) {
    step = value; desktop.dataset.step = String(step);
    $('step-number').textContent = '0'+(step+1)+' / 04';
    $('demo-instruction').textContent = captions[step];
    $('floating-wheel').hidden = step !== 2;
    $('sample-output').hidden = step !== 3;
    source.classList.toggle('picked',step === 1 || step === 2);
    const cursor=$('tour-cursor');
    if(step<2){const d=desktop.getBoundingClientRect(),f=source.getBoundingClientRect();cursor.style.left=(f.left-d.left+f.width*.7)+'px';cursor.style.top=(f.top-d.top+f.height*.75)+'px';}
    else {cursor.style.left='57%';cursor.style.top='42%';}
    $('next-step').textContent = step === 3 ? '↻' : '→';
    $('next-step').setAttribute('aria-label',step === 3 ? 'Replay Example' : 'Next Step');
    $('next-step').title = step === 3 ? 'Replay Example' : 'Next Step';
    if (step === 2) drawWheel();
    if (step === 3) showResult(operations()[selected] || operations()[0]);
  }
  function point(radius,angle) { return [210+radius*Math.sin(angle),210-radius*Math.cos(angle)]; }
  function sector(index,count) {
    const width=2*Math.PI/count, a=index*width-width/2+.026, b=(index+1)*width-width/2-.026;
    const p=point(193,a), q=point(193,b), r=point(67,b), s=point(67,a);
    const large=count===1?1:0;return `M${p}A193 193 0 ${large} 1 ${q}L${r}A67 67 0 ${large} 0 ${s}Z`;
  }
  function drawWheel() {
    const all=operations(), pages=Math.max(1,Math.ceil(all.length/8));
    wheelPage=Math.min(wheelPage,pages-1);
    const items=all.slice(wheelPage*8,wheelPage*8+8);
    svg.replaceChildren();
    items.forEach((op,i) => {
      const ns='http://www.w3.org/2000/svg', g=document.createElementNS(ns,'g');
      const global=wheelPage*8+i, p=document.createElementNS(ns,'path'), t=document.createElementNS(ns,'text');
      g.setAttribute('class','wheel-choice'+(global === selected?' selected':''));g.dataset.index=String(global);
      g.setAttribute('role','button');g.setAttribute('tabindex','0');
      g.setAttribute('aria-label',op.title+(op.engine?' · requires '+op.engine:''));
      p.setAttribute('d',sector(i,items.length));g.append(p);
      const position=point(132,2*Math.PI*i/items.length);
      const words=op.title.replace('…','').split(' '), lines=op.title.length>13 && words.length>1 ? [words.slice(0,-1).join(' '),words.at(-1)] : [op.title];
      t.setAttribute('x',position[0]);t.setAttribute('y',position[1]-(lines.length-1)*9+5);
      lines.forEach((line,j) => {const span=document.createElementNS(ns,'tspan');span.setAttribute('x',position[0]);span.setAttribute('dy',j?'19':'0');span.textContent=line;t.append(span);});
      g.append(t);g.addEventListener('click',()=>choose(global));
      g.addEventListener('keydown',e=>{if(['Enter',' '].includes(e.key)){e.preventDefault();e.stopPropagation();choose(global);}});
      svg.append(g);
    });
    $('wheel-page').textContent=(wheelPage+1)+' / '+pages;document.querySelector('.wheel-pages').hidden=pages===1;
    $('wheel-prev').disabled=pages===1;$('wheel-next').disabled=pages===1;
  }
  function showResult(op) {
    if (!op) return;
    let name,detail;
    if (op.extension) {name=stem(sample().name)+'.'+op.extension;detail='Sample copy · original kept'+(op.engine?' · '+op.engine:'');}
    else if(op.id==='archive.extract'){name=stem(sample().name)+'/';detail='Sample extracted folder · archive kept';}
    else {name=op.title;detail=op.detail+'. In the Mac app.';}
    $('output-name').textContent=name;$('output-detail').textContent=detail;
    $('demo-instruction').textContent=op.extension?'Example: '+name+' · original kept.':'Example: '+op.title+'.';
  }
  function choose(index) {stopTour();selected=index;setStep(3);announce($('demo-instruction').textContent);}
  function chooseMode(value) {stopTour();mode=value;wheelPage=0;selected=0;updateModes();setStep(2);}
  grid.addEventListener('click',e=>{
    const file=e.target.closest('[data-sample]');if(!file)return;
    if(suppressClick){suppressClick=false;return;}
    stopTour();const index=sampleFiles.indexOf(file);
    if(index!==sampleIndex){sampleIndex=index;setSample();}
    setStep(step===2?0:1);desktop.focus({preventScroll:true});
  });
  $('next-step').addEventListener('click',()=>{stopTour();setStep(step===3?0:step+1);announce($('demo-instruction').textContent);});
  $('tour-toggle').addEventListener('click',()=>{autoplay=!autoplay;updatePlay();if(autoplay&&step===3)setStep(0);schedule();});
  document.querySelectorAll('[data-mode]').forEach(b=>b.addEventListener('click',()=>chooseMode(b.dataset.mode)));
  $('wheel-cancel').addEventListener('click',()=>{stopTour();setStep(0);announce('Example cancelled. Original unchanged.');source.focus({preventScroll:true});});
  for(const [id,direction] of [['wheel-prev',-1],['wheel-next',1]]) $(id).addEventListener('click',()=>{const pages=Math.ceil(operations().length/8);wheelPage=(wheelPage+direction+pages)%pages;selected=wheelPage*8;drawWheel();});
  for(const origin of ['desktop','finder']) $('origin-'+origin).addEventListener('click',()=>{
    stopTour();desktop.dataset.origin=origin;
    for(const x of ['desktop','finder']) $('origin-'+x).setAttribute('aria-pressed',String(x===origin));
    setStep(0);
  });
  desktop.addEventListener('keydown',e=>{
    if(e.target.closest('select,input,textarea'))return;
    if(['Shift','Meta','Control'].includes(e.key)){e.preventDefault();chooseMode({Shift:'convert',Meta:'tools',Control:'actions'}[e.key]);}
    else if(e.key==='Escape'){e.preventDefault();stopTour();setStep(0);}
    else if(step===2 && ['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){e.preventDefault();const all=operations();selected=(selected+(['ArrowLeft','ArrowUp'].includes(e.key)?-1:1)+all.length)%all.length;wheelPage=Math.floor(selected/8);drawWheel();}
    else if(e.key==='Enter' && e.target===desktop){e.preventDefault();if(step===2)choose(selected);else{stopTour();setStep(1);}}
  });
  grid.addEventListener('pointerdown',e=>{
    const file=e.target.closest('[data-sample]');if(e.button!==0||!file)return;
    stopTour();const index=sampleFiles.indexOf(file);
    if(index!==sampleIndex){sampleIndex=index;setSample();}
    pointer={id:e.pointerId,x:e.clientX,y:e.clientY,moved:false};source.setPointerCapture(e.pointerId);
  });
  grid.addEventListener('pointermove',e=>{
    if(!pointer||pointer.id!==e.pointerId)return;
    if(!pointer.moved && Math.hypot(e.clientX-pointer.x,e.clientY-pointer.y)>8){
      pointer.moved=true;stopTour();setStep(1);desktop.focus({preventScroll:true});
      const ghost=document.createElement('span');ghost.id='drag-ghost';ghost.className='drag-ghost';ghost.textContent=sample().name;desktop.append(ghost);
    }
    if(pointer.moved){e.preventDefault();const rect=desktop.getBoundingClientRect(),ghost=$('drag-ghost');ghost.style.left=(e.clientX-rect.left)+'px';ghost.style.top=(e.clientY-rect.top)+'px';
      const hit=document.elementFromPoint(e.clientX,e.clientY)?.closest('.wheel-choice');
      svg.querySelectorAll('.wheel-choice').forEach(g=>g.classList.toggle('selected',g===hit));
    }
  });
  function finishDrag(e,cancel=false){
    if(!pointer||pointer.id!==e.pointerId)return;
    if(pointer.moved){suppressClick=true;const hit=cancel?null:document.elementFromPoint(e.clientX,e.clientY)?.closest('.wheel-choice');
      if(hit)choose(Number(hit.dataset.index));else setStep(0);
      $('drag-ghost')?.remove();setTimeout(()=>{suppressClick=false;},0);
    }
    pointer=null;
  }
  grid.addEventListener('pointerup',e=>finishDrag(e));grid.addEventListener('pointercancel',e=>finishDrag(e,true));
  desktop.addEventListener('dragover',e=>e.preventDefault());desktop.addEventListener('drop',e=>{e.preventDefault();announce('Choose One Of The Sample Files. No Files Are Uploaded.');});
  reduced.addEventListener('change',()=>{if(reduced.matches)stopTour();});
  document.addEventListener('visibilitychange',()=>{if(document.hidden){clearTimeout(timer);}else schedule();});
  if('IntersectionObserver' in window)new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;schedule();},{threshold:.15}).observe(desktop);

  $('format-count').textContent=data.counts.formats;$('tool-count').textContent=data.counts.tools;$('action-count').textContent=data.counts.actions;
  $('format-directory').innerHTML=data.samples.map(s=>'<div class="format-row"><h3>'+esc(s.label)+'</h3><p class="format-list">'+(s.formats.length?s.formats.map(x=>esc(x.toUpperCase())).join(' · '):'ZIP · TAR · GZIP · Extract')+'</p><div class="format-engine">'+renderNotes(nativeNotes[s.id])+'</div></div>').join('');
  const prefixes={image:'Image',pdf:'PDF',media:'Media',document:'Document',archive:'Archive',action:''};
  $('tool-directory').innerHTML=[['File Tools',data.tools],['File Actions',data.actions]].map(([title,list])=>'<div><h3>'+title+'</h3><ul>'+list.map(op=>'<li>'+esc((prefixes[op.id.split('.')[0]]+' '+op.title).trim())+'</li>').join('')+'</ul></div>').join('');
  const themes={orchard:'#14251D',pistachio:'#FFF9EB',lemonade:'#FFFAED'};
  function theme(value){const chosen=Object.hasOwn(themes,value)?value:'orchard';document.documentElement.dataset.theme=chosen;$('appearance').value=chosen;document.querySelector('meta[name="theme-color"]').content=themes[chosen];}
  try{theme(localStorage.getItem('lemulip.appearance'));}catch{theme('orchard');}
  $('appearance').onchange=e=>{theme(e.target.value);try{localStorage.setItem('lemulip.appearance',e.target.value);}catch{}};
  setSample();updatePlay();schedule();$('load-warning').hidden=true;
})();
