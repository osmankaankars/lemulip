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
  let feature = 'images', edit = {}, audioContext = null, audioFrame = null;
  const sample = () => data.samples[sampleIndex];
  const stem = name => name.replace(/\.[^.]+$/, '');
  const announce = text => { $('announcer').textContent = text; };
  const icons = {images:'HEIC',pdf:'PDF',audio:'WAV',video:'MOV',documents:'MD',spreadsheets:'CSV',presentations:'PPTX',subtitles:'SRT',archives:'ZIP'};
  const nativeNotes = {
    images:[['Built In','PNG, JPG, HEIC, TIFF, BMP And PDF.'],['Optional','ImageMagick For WebP And AVIF.']],
    pdf:[['Built In','PDF Tools And Offline OCR.'],['Text','Selectable Text Or OCR Required.']],
    audio:[['Built In','M4A, WAV And AIFF Where Codecs Allow.'],['Optional','FFmpeg For Other Targets.']],
    video:[['Built In','MP4, MOV And M4A Where Codecs Allow.'],['Optional','FFmpeg For Other Targets.']],
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
    $('workspace-status').textContent = '9 Files';
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
    if (step === 2) { drawWheel(); $('workspace-status').textContent = 'Choose An Operation'; }
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
    $('workspace-status').textContent = name;
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
  for(const origin of ['desktop','finder','workspace']) $('origin-'+origin).addEventListener('click',()=>{
    stopTour();desktop.dataset.origin=origin;
    for(const x of ['desktop','finder','workspace']) $('origin-'+x).setAttribute('aria-pressed',String(x===origin));
    setStep(0); $('workspace-status').textContent='9 Files';
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
  desktop.addEventListener('dragover',e=>e.preventDefault());desktop.addEventListener('drop',e=>{e.preventDefault();announce('Please use the sample selector. This website does not read your files.');});
  reduced.addEventListener('change',()=>{if(reduced.matches)stopTour();});
  document.addEventListener('visibilitychange',()=>{if(document.hidden){clearTimeout(timer);stopSound();$('sample-video')?.pause();}else schedule();});
  if('IntersectionObserver' in window)new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;schedule();},{threshold:.15}).observe(desktop);

  const features={
    images:{title:'Keep the part you love.',summary:'Change the crop, then preview the new composition. The original stays untouched.',editor:'Crop image',button:'Preview crop',facts:[['Tools','Crop · Resize · Compress · Rotate · Flip · Remove Metadata'],['Conversion targets','PNG · JPG · HEIC · TIFF · WebP · AVIF · BMP · PDF']]},
    pdf:{title:'Every page in its place.',summary:'Swap pages and rotate the first one. Your sample result follows the order you choose.',editor:'Organize PDF',button:'Preview arranged PDF',facts:[['Tools','Organize · Merge · Split · Extract · Rotate · Compress · OCR'],['Built in','PDFKit and offline text recognition']]},
    audio:{title:'Just the part worth keeping.',summary:'Set the start and end points. Hear a generated sample tone, then preview the shorter copy.',editor:'Trim audio',button:'Preview audio trim',facts:[['Tools','Trim · Compress · Change Speed · Adjust Volume'],['Native export','M4A · WAV · AIFF, where codecs allow']]},
    video:{title:'Make the cut.',summary:'Play the sample clip and choose your range. Preview a trimmed copy without touching the original.',editor:'Trim video',button:'Preview video trim',facts:[['Tools','Trim · Crop · Compress · Resize · Mute · Extract Audio · Speed · Volume'],['Native export','MP4 · MOV, where codecs allow']]},
    documents:{title:'Notes, ready for their next app.',summary:'Edit the sample Markdown. Preview how the heading and text become a simple document.',editor:'Markdown to Word',button:'Preview Word document',facts:[['Built in','TXT · basic RTF · basic Markdown → DOCX'],['More complex documents','Optional local LibreOffice and Pandoc routes']]},
    spreadsheets:{title:'A table, without the busywork.',summary:'Pick a sample CSV and preview its worksheet. Leading zeros and formula-like strings stay as text.',editor:'CSV to Excel',button:'Preview worksheet',facts:[['Built in','CSV / TSV → XLSX · CSV ↔ TSV'],['Values preserved','One worksheet; cells are text, not formulas']]},
    presentations:{title:'A deck, ready to share.',summary:'Choose a sample deck and preview its slides as document pages.',editor:'Slides to PDF',button:'Preview PDF pages',facts:[['Conversion targets','PDF · PPTX · ODP'],['Local engine','LibreOffice required; complex layouts may change']]},
    subtitles:{title:'Keep the words. Keep the timing.',summary:'Switch the sample language and preview WebVTT. Cue timing and Unicode text stay readable.',editor:'SRT to WebVTT',button:'Preview WebVTT',facts:[['Built in','SRT ↔ VTT · TXT export'],['Timing','Hours, minutes, seconds and milliseconds retained']]},
    archives:{title:'A little more together.',summary:'Choose which sample files to pack. The archive preview includes only your selection.',editor:'Create ZIP',button:'Preview ZIP archive',facts:[['Create','ZIP · TAR · GZIP individual files'],['Extract','Supported archives → a new folder']]}
  };
  const details = facts => '<dl>'+facts.map(([a,b])=>'<div><dt>'+esc(a)+'</dt><dd>'+esc(b)+'</dd></div>').join('')+'</dl>';
  function stopSound(){if(audioFrame)cancelAnimationFrame(audioFrame);audioFrame=null;if(audioContext){audioContext.close().catch(()=>{});audioContext=null;}const b=$('play-tone');if(b)b.textContent='Hear selection';}
  function papers(){return '<div class="pdf-pages">'+edit.order.map((n,i)=>'<div class="paper"'+(i===0&&edit.rotation?' style="transform:rotate('+edit.rotation+'deg) scale(.72)"':'')+'><b>'+['Field notes','The details','What’s next'][n-1]+'</b><div class="paper-color"></div><i></i><i></i><i></i><small>Page '+n+'</small></div>').join('')+'</div>';}
  function timeControls(duration){return '<label>Start <input id="range-start" type="range" min="0" max="'+(duration-.5)+'" step=".5" value="1"><output id="start-label">1s</output></label><label>End <input id="range-end" type="range" min=".5" max="'+duration+'" step=".5" value="'+(duration-1)+'"><output id="end-label">'+(duration-1)+'s</output></label>';}
  function selectFeature(id,focus=false){
    stopSound();$('sample-video')?.pause();feature=id;edit={crop:16,order:[1,2,3],rotation:0,start:1,end:id==='video'?3:7,deck:0,language:'en',table:0};
    document.querySelectorAll('[data-feature]').forEach(tab=>{const active=tab.dataset.feature===id;tab.setAttribute('aria-selected',String(active));tab.tabIndex=active?0:-1;});
    const f=features[id];$('feature-panel').setAttribute('aria-labelledby','tab-'+id);$('sample-workbench').dataset.family=id;$('sample-workbench').dataset.result='false';
    $('editor-title').textContent=f.editor;$('feature-title').textContent=f.title;$('feature-summary').textContent=f.summary;
    $('feature-details').innerHTML=details(f.facts);$('run-example').textContent=f.button+' →';$('run-example').disabled=false;$('example-output').hidden=true;
    const board=$('sample-workbench'), controls=$('edit-controls');board.innerHTML='';controls.innerHTML='';
    if(id==='images'){
      board.innerHTML='<div class="crop-stage"><img src="./assets/morning-light.jpg" width="384" height="288" alt="Sample landscape"><div class="crop-selection"></div></div>';
      controls.innerHTML='<label>Crop inset <input id="crop-inset" type="range" min="5" max="32" value="16"><output id="crop-value">16%</output></label>';
      $('crop-inset').addEventListener('input',e=>{edit.crop=Number(e.target.value);$('crop-value').textContent=edit.crop+'%';board.querySelector('.crop-selection').style.inset=edit.crop+'%';$('example-output').hidden=true;});
    }else if(id==='pdf'){
      board.innerHTML=papers();controls.innerHTML='<button id="swap-pages">Swap first two pages</button><button id="rotate-page">Rotate first page</button>';
      $('swap-pages').onclick=()=>{
        [edit.order[0],edit.order[1]]=[edit.order[1],edit.order[0]];board.innerHTML=papers();$('example-output').hidden=true;
        if(!reduced.matches)board.querySelectorAll('.paper').forEach((paper,i)=>{if(i<2&&paper.animate)paper.animate([{transform:'translateX('+(i===0?110:-110)+'%)'},{transform:'translateX(0)'}],{duration:420,easing:'ease-out'});});
      };
      $('rotate-page').onclick=()=>{edit.rotation=(edit.rotation+90)%360;board.innerHTML=papers();$('example-output').hidden=true;};
    }else if(id==='audio'){
      const bars=Array.from({length:50},(_,i)=>'<i style="height:'+(18+Math.abs(Math.sin(i*.8)*Math.cos(i*.17))*80)+'%"></i>').join('');
      board.innerHTML='<div class="wave-scene"><p>voice-note.wav · generated 8-second sample tone</p><div class="waveform">'+bars+'<div class="wave-select"></div></div><div class="wave-times"><span>0:00</span><span>0:04</span><span>0:08</span></div></div>';
      controls.innerHTML=timeControls(8)+'<button id="play-tone">Hear selection</button>';
      $('play-tone').onclick=playTone;
    }else if(id==='video'){
      board.innerHTML='<div class="media-frame"><video id="sample-video" src="./assets/sample-walk.mp4" poster="./assets/morning-light.jpg" controls muted playsinline preload="metadata" aria-label="Generated four-second landscape sample, not a native app recording"></video></div>';
      controls.innerHTML=timeControls(4)+'<button id="play-video">Play selected range</button>';
      const video=$('sample-video');$('play-video').onclick=()=>{video.currentTime=edit.start;video.play().catch(()=>announce('Use the video controls to start playback.'));};
      video.addEventListener('timeupdate',()=>{if(video.currentTime>=edit.end)video.pause();});
    }else if(id==='documents'){
      board.innerHTML='<div class="document-preview"><div class="sheet"><small>weekend-notes.md</small><pre id="markdown-source"># Weekend notes\n\nPack light.\nTake the scenic route.</pre></div><div class="sheet" id="word-preview"><small>Document preview</small><h4>Weekend notes</h4><p>Pack light.<br>Take the scenic route.</p></div></div>';
      controls.innerHTML='<label for="note-title">Heading</label><input id="note-title" type="text" value="Weekend notes" maxlength="60" aria-label="Sample note heading">';
      $('note-title').oninput=e=>{edit.heading=e.target.value;$('markdown-source').textContent='# '+edit.heading+'\n\nPack light.\nTake the scenic route.';$('example-output').hidden=true;};
    }else if(id==='spreadsheets'){
      controls.innerHTML='<label>Sample <select id="table-sample"><option value="0">Inventory · leading zeros</option><option value="1">Codes · formula-like text</option></select></label>';renderTable();
      $('table-sample').onchange=e=>{edit.table=Number(e.target.value);renderTable();$('example-output').hidden=true;};
    }else if(id==='presentations'){
      controls.innerHTML='<label>Deck <select id="deck-sample"><option value="0">Project update</option><option value="1">Field notes</option></select></label>';renderSlides();
      $('deck-sample').onchange=e=>{edit.deck=Number(e.target.value);renderSlides();$('example-output').hidden=true;};
    }else if(id==='subtitles'){
      controls.innerHTML='<label>Sample <select id="caption-language"><option value="en">English</option><option value="tr">Turkish</option></select></label>';renderCaptions();
      $('caption-language').onchange=e=>{edit.language=e.target.value;renderCaptions();$('example-output').hidden=true;};
    }else{
      board.innerHTML='<div class="archive-preview"><div class="archive-items"><span>field-notes.pdf</span><span>morning-light.png</span><span>inventory.csv</span></div><div class="archive-box"><i></i><b>weekend.zip</b></div></div>';
      controls.innerHTML=['PDF','Image','CSV'].map((n,i)=>'<label><input type="checkbox" data-archive="'+i+'" checked>'+n+'</label>').join('');
      controls.querySelectorAll('input').forEach(input=>input.onchange=()=>{const checks=[...controls.querySelectorAll('input')];checks.forEach((c,i)=>board.querySelectorAll('.archive-items span')[i].style.opacity=c.checked?'1':'.3');$('run-example').disabled=!checks.some(c=>c.checked);$('example-output').hidden=true;});
    }
    if(id==='audio'||id==='video'){
      const duration=id==='audio'?8:4;
      for(const side of ['start','end']) $('range-'+side).oninput=e=>{
        stopSound();$('sample-video')?.pause();edit[side]=Number(e.target.value);
        if(edit.start>=edit.end){if(side==='start')edit.end=Math.min(duration,edit.start+.5);else edit.start=Math.max(0,edit.end-.5);}
        for(const x of ['start','end']){$('range-'+x).value=edit[x];$(x+'-label').textContent=edit[x]+'s';}
        const selection=board.querySelector('.wave-select');if(selection){selection.style.left=edit.start/duration*100+'%';selection.style.right=(duration-edit.end)/duration*100+'%';}
        $('example-output').hidden=true;
      };
      if(id==='audio'){board.querySelector('.wave-select').style.left='12.5%';board.querySelector('.wave-select').style.right='12.5%';}
    }
    if(focus){$('tab-'+id).focus({preventScroll:true});$('tab-'+id).scrollIntoView({block:'nearest',inline:'nearest'});}
  }
  function renderTable(){
    const rows=edit.table?[['Code','Value'],['0007','=1+1'],['0008','00123']]:[['Code','Item'],['0012','Notebook'],['0013','Pencil'],['0014','Folder']];
    $('sample-workbench').innerHTML='<div class="document-preview"><div class="sheet"><small>inventory.csv</small><pre>'+esc(rows.map(r=>r.join(',')).join('\n'))+'</pre></div><div class="sheet"><small>inventory.xlsx</small><table>'+rows.map((r,i)=>'<tr>'+r.map(c=>'<'+(i?'td':'th')+'>'+esc(c)+'</'+(i?'td':'th')+'>').join('')+'</tr>').join('')+'</table></div></div>';
  }
  function renderSlides(){const titles=edit.deck?['Field notes','The route']:['Project update','What’s next'];$('sample-workbench').innerHTML='<div class="slide-preview">'+titles.map((title,i)=>'<div class="slide-card"><small>0'+(i+1)+'</small><h4>'+title+'</h4><p>'+['A new perspective.','A clear next step.'][i]+'</p></div>').join('')+'</div>';}
  function captionText(){return edit.language==='tr'?'Günaydın.\n\n2\n00:00:02,000 --> 00:00:04,000\nYola çıkalım.':'Good morning.\n\n2\n00:00:02,000 --> 00:00:04,000\nLet’s take the scenic route.';}
  function renderCaptions(){const srt='1\n00:00:00,000 --> 00:00:02,000\n'+captionText();edit.vtt='WEBVTT\n\n'+srt.replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g,'$1.$2');$('sample-workbench').innerHTML='<div class="document-preview"><div class="sheet"><small>captions.srt</small><pre>'+esc(srt)+'</pre></div><div class="sheet"><small>captions.vtt</small><pre>'+esc(edit.vtt)+'</pre></div></div>';}
  async function playTone(){
    if(audioContext){stopSound();return;}
    const Audio=window.AudioContext||window.webkitAudioContext;if(!Audio){announce('Audio playback is not available in this browser. The trim example still works.');return;}
    const context=new Audio();audioContext=context;
    try{await context.resume();if(audioContext!==context)return;
      const oscillator=context.createOscillator(),gain=context.createGain(),duration=edit.end-edit.start,now=context.currentTime;
      oscillator.type='sine';[261.63,329.63,392,523.25].forEach((f,i)=>oscillator.frequency.setValueAtTime(f,now+duration*i/4));
      gain.gain.setValueAtTime(0,now);gain.gain.linearRampToValueAtTime(.07,now+.05);gain.gain.setValueAtTime(.07,now+Math.max(.06,duration-.1));gain.gain.linearRampToValueAtTime(0,now+duration);
      oscillator.connect(gain);gain.connect(context.destination);oscillator.start(now);oscillator.stop(now+duration);$('play-tone').textContent='Stop sample';
      oscillator.onended=()=>{if(audioContext===context)stopSound();};
    }catch{stopSound();announce('Playback could not start. Your trim selection is still available.');}
  }
  $('run-example').onclick=()=>{
    const output=$('example-output');let name='',message='';
    if(feature==='images'){name='morning-light-cropped.png';message='Crop inset '+edit.crop+'% · sample composition updated · original kept.';}
    if(feature==='pdf'){name='field-notes-arranged.pdf';message='Page order: '+edit.order.join(' → ')+'. First page rotation: '+edit.rotation+'°.';}
    if(feature==='audio'||feature==='video'){name=feature==='audio'?'voice-note-trimmed.wav':'morning-walk-trimmed.mp4';message='Selection: '+edit.start+'s → '+edit.end+'s · '+(edit.end-edit.start)+' seconds. Original kept.';}
    if(feature==='documents'){name='weekend-notes.docx';$('word-preview').querySelector('h4').textContent=edit.heading||'Weekend notes';message='Heading and paragraphs shown as a simple document. Original kept.';}
    if(feature==='spreadsheets'){name='inventory.xlsx';message='One worksheet. Values remain text, including leading zeros and formula-like strings.';}
    if(feature==='presentations'){name='project-deck.pdf';message='2 sample slides → 2 PDF pages. The Mac app uses LibreOffice for this route.';}
    if(feature==='subtitles'){name='captions.vtt';message='2 cues · WebVTT header · millisecond timing and Unicode text preserved.';}
    if(feature==='archives'){name='weekend.zip';const included=[...$('edit-controls').querySelectorAll('input')].flatMap((c,i)=>c.checked?[['field-notes.pdf','morning-light.png','inventory.csv'][i]]:[]);if(!included.length)return;message=included.length+' sample file'+(included.length===1?'':'s')+': '+included.join(', ')+'. Originals kept.';}
    output.replaceChildren();const title=document.createElement('b');title.textContent='Sample result: '+name;output.append(title,document.createTextNode(message));
    if(feature==='images'){
      const original=$('sample-workbench').querySelector('img'),canvas=document.createElement('canvas'),inset=edit.crop/100;
      canvas.width=Math.round(original.naturalWidth*(1-2*inset));canvas.height=Math.round(original.naturalHeight*(1-2*inset));
      const context=canvas.getContext('2d');if(context&&canvas.width&&canvas.height){
        context.drawImage(original,original.naturalWidth*inset,original.naturalHeight*inset,canvas.width,canvas.height,0,0,canvas.width,canvas.height);
        const image=document.createElement('img');image.src=canvas.toDataURL('image/png');image.alt='Cropped sample composition';image.className='mini-photo';output.prepend(image);
      }
    }
    $('sample-workbench').dataset.result='true';
    output.hidden=false;output.dataset.result=feature;announce(title.textContent+'. '+message);
  };
  $('reset-example').onclick=()=>selectFeature(feature);
  $('try-this-file').onclick=()=>{stopTour();sampleIndex=data.samples.findIndex(s=>s.id===feature);setSample();};
  const tabs=[...document.querySelectorAll('[data-feature]')];
  tabs.forEach((tab,i)=>{tab.onclick=()=>selectFeature(tab.dataset.feature);tab.addEventListener('keydown',e=>{
    let index;if(e.key==='ArrowRight')index=(i+1)%tabs.length;else if(e.key==='ArrowLeft')index=(i+tabs.length-1)%tabs.length;else if(e.key==='Home')index=0;else if(e.key==='End')index=tabs.length-1;else return;
    e.preventDefault();selectFeature(tabs[index].dataset.feature,true);
  });});
  $('format-count').textContent=data.counts.formats;$('tool-count').textContent=data.counts.tools;$('action-count').textContent=data.counts.actions;
  $('format-directory').innerHTML=data.samples.map(s=>'<div class="format-row"><h3>'+esc(s.label)+'</h3><p class="format-list">'+(s.formats.length?s.formats.map(x=>esc(x.toUpperCase())).join(' · '):'ZIP · TAR · GZIP · Extract')+'</p><div class="format-engine">'+renderNotes(nativeNotes[s.id])+'</div></div>').join('');
  const prefixes={image:'Image',pdf:'PDF',media:'Media',document:'Document',archive:'Archive',action:''};
  $('tool-directory').innerHTML=[['26 file tools',data.tools],['6 file actions',data.actions]].map(([title,list])=>'<div><h3>'+title+'</h3><ul>'+list.map(op=>'<li>'+esc((prefixes[op.id.split('.')[0]]+' '+op.title).trim())+'</li>').join('')+'</ul></div>').join('');
  const themes={orchard:'#14251D',pistachio:'#FFF9EB',lemonade:'#FFFAED'};
  function theme(value){const chosen=Object.hasOwn(themes,value)?value:'orchard';document.documentElement.dataset.theme=chosen;$('appearance').value=chosen;document.querySelector('meta[name="theme-color"]').content=themes[chosen];}
  try{theme(localStorage.getItem('lemulip.appearance'));}catch{theme('orchard');}
  $('appearance').onchange=e=>{theme(e.target.value);try{localStorage.setItem('lemulip.appearance',e.target.value);}catch{}};
  setSample();selectFeature('images');updatePlay();schedule();$('load-warning').hidden=true;
})();
