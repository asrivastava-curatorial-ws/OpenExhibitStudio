'use strict';
const $=id=>document.getElementById(id);
const mode=location.pathname==='/host'?'host':location.pathname==='/display'?'display':'player';
const key='oes-quiz-'+mode+'-'+location.host;
let token=(mode==='host'?sessionStorage:localStorage).getItem(key)||'';
if(mode==='host'&&location.hash.length>1){token=location.hash.slice(1);sessionStorage.setItem(key,token);history.replaceState(null,'',location.pathname);}
document.body.className=mode;
$('role').textContent={player:'Participant',host:'Host console',display:'Projector'}[mode];
let state=null,lastMain='',lastSide='',lastMessages='',busy=false,deadline=0,joined=false,editing=null,editIndex=0,stopped=false;
const names={choice:'Pick one',multiple:'Pick several',text:'Type an answer',number:'Numeric answer',order:'Correct order',match:'Match pairs',category:'Categorise',poll:'Audience poll',scale:'Rating scale',cloud:'Word cloud',slide:'Content slide'};
const publicNames={practice:'Self-paced play',lobby:'Lobby',open:'Accepting answers',closed:'Time is up',paused:'Paused',reveal:'Round result',standings:'Leaderboard',finished:'Final standings'};
function el(tag,text,cls){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;}
function btn(text,fn,cls){const b=el('button',text,cls);b.type='button';b.addEventListener('click',()=>Promise.resolve().then(fn).catch(fail));return b;}
function field(label,control){control.setAttribute('aria-label',label);const l=el('label',undefined,'field');l.append(document.createTextNode(label),control);return l;}
function input(type,value){const i=el('input');i.type=type;i.value=value??'';return i;}
function select(opts,value){const s=el('select');for(const [v,label] of opts){const o=el('option',label);o.value=v;s.append(o);}s.value=value??opts[0]?.[0];return s;}
function clear(e,...children){e.replaceChildren(...children);}
function fail(e){$('error').textContent=e.message||String(e);$('error').hidden=false;}
function message(text,cls='muted'){return el('p',text,cls);}
async function api(path,body,withToken=true){const headers={};if(withToken&&token)headers.Authorization='Bearer '+token;
 const opts={headers,cache:'no-store'};if(body!==undefined){headers['Content-Type']='application/json';opts.method='POST';opts.body=JSON.stringify(body);}
 const r=await fetch(path,opts);const d=await r.json();if(!r.ok){const err=new Error(d.error||'Request failed');err.status=r.status;throw err;}return d;}
async function refresh(){if(busy||stopped)return;busy=true;
 try{const s=await api(mode==='host'?'/api/host/state':'/api/state');state=s;deadline=performance.now()+s.seconds_left*1000;joined=!!s.me;
 $('connection').textContent='Connected';render(s);}
 catch(e){if(mode==='player'&&e.status===403&&token){token='';localStorage.removeItem(key);lastMain='';}else if(e.status===403&&mode==='host'){stopped=true;fail(e);}else{$('connection').textContent='Reconnecting…';}}
 finally{busy=false;}}
async function action(act,more={}){const s=state;await api('/api/host/action',{action:act,phase:s.phase,round:s.index,...more});$('error').hidden=true;await refresh();}
function joinForm(s){
 const joinKey=JSON.stringify([s.code,s.teams]);if($('join').childElementCount&&$('join').dataset.room===joinKey)return;
 const box=$('join'),f=el('form');box.dataset.room=joinKey;
 const name=input('text',''),code=input('text',new URLSearchParams(location.search).get('room')||''),team=select(s.teams.map(x=>[x,x]));
 name.maxLength=32;name.required=true;name.autocomplete='nickname';code.required=true;code.inputMode='numeric';code.maxLength=6;
 f.append(field('Room code',code),field('Display name',name));if(s.teams.length)f.append(field('Team',team));
 const b=el('button','Join contest','primary');b.type='submit';f.append(b);
 f.onsubmit=async e=>{e.preventDefault();try{const a=await api('/api/join',{name:name.value,code:code.value,team:team.value},false);token=a.token;localStorage.setItem(key,token);$('error').hidden=true;lastMain='';await refresh();}catch(err){fail(err);}};
 clear(box,el('h2','Join this contest'),f);
}
function render(s){
 $('phase').textContent=(s.index<0?'':('Round '+(s.index+1)+' of '+s.rounds+' · '))+publicNames[s.phase];
 $('title').textContent=s.title;$('code').textContent=(mode==='player'?'':'Room ')+s.code;
 const login=mode==='player'&&!joined;$('join').hidden=!login;
 if(login){joinForm(s);$('discussion').hidden=true;return;}
 const signature=JSON.stringify([s.code,s.index,s.phase,s.question,s.me?.submitted,s.answer,s.distribution,s.leaders,s.team_leaders,s.explanation,s.session_phase,s.total_score]);
 if(signature!==lastMain){main(s);lastMain=signature;}
 const aside=JSON.stringify([s.code,s.phase,s.index,s.locked,s.players,s.rounds,s.me?.name,s.me?.team,s.deck?.title]);
 if(aside!==lastSide){side(s);lastSide=aside;}
 const count=$('count');if(count)count.textContent=s.received+' / '+s.players+' answered';
 const msg=JSON.stringify([s.qa,s.phase==='finished',joined]);
 if(msg!==lastMessages){discussion(s);lastMessages=msg;}
 tick();
}
function main(s){
 const box=$('stage');clear(box);
 if(s.phase==='practice'){box.append(el('h2','Self-paced contest in progress'),message('Each participant advances through the rounds on their device.'));return;}
 if(s.self_paced&&s.session_phase==='practice'&&mode==='player'){
  const advance=()=>api('/api/practice/next',{round:s.index}).then(refresh);
  if(s.phase==='lobby'){box.append(el('h2','Ready to play?'),btn('Begin my rounds',advance,'primary'));return;}
  if(s.phase==='finished'){box.append(el('h2','You finished'),message('Your total: '+s.total_score+' points. Final standings appear when the host closes the contest.'));return;}
 }
 if(s.phase==='lobby'){box.append(el('h2',mode==='host'?'Ready to begin':'Waiting for the first round'),message(mode==='host'?'Open the projector view and invite the audience to join.':'The host will start the contest here.'));return;}
 const stats=el('div',undefined,'stats'),timer=el('b','','timer'),count=el('span','','metric');timer.id='timer';count.id='count';stats.append(timer,count);box.append(stats);
 if(['standings','finished'].includes(s.phase)){box.append(el('h2',s.phase==='finished'?'Final standings':'Leaderboard'));ranking(box,s);return;}
 const q=s.question;box.append(el('div',names[q.type]+(q.points?' · '+q.points+' pts':''),'tag'),el('h2',q.prompt));
 if(q.image){const im=el('img');im.src=q.image;im.alt='Question illustration';im.className='questionImage';box.append(im);}
 if(mode==='player'&&s.self_paced&&s.phase==='open'&&q.type==='slide'){box.append(message('The next round becomes available when this slide’s timer ends.'));}
 if(mode==='player'&&s.phase==='open'&&!s.me.submitted&&q.type!=='slide'){responseForm(box,q,s.index);return;}
 if(q.options&&!['standings','finished'].includes(s.phase))for(const v of q.options)box.append(el('div',v,'option'));
 if(q.labels)box.append(message('Items: '+q.labels.join(' · ')));
 if(s.phase==='paused'||s.phase==='closed')box.append(message(s.phase==='paused'?'The host paused the clock.':'Answers are closed. The host will reveal the result.','stateNote'));
 if(s.me?.submitted&&s.phase!=='reveal')box.append(message('Answer recorded','stateNote'));
 if(s.phase==='reveal'){if(s.self_paced&&s.session_phase==='practice'&&mode==='player')box.append(btn(s.index+1<s.rounds?'Next question':'Finish my quiz',()=>api('/api/practice/next',{round:s.index}).then(refresh),'primary'));
 if(s.answer!==null&&s.answer!==undefined){
   const a=Array.isArray(s.answer)?s.answer.map((x,i)=>q.labels?q.labels[i]+' → '+x:x).join(q.type==='order'?' → ':' · '):String(s.answer);
   box.append(el('h3','Answer'),message(a,'stateNote'));}
   if(s.explanation)box.append(message(s.explanation));if(s.me)box.append(message('Your score this round: '+(s.me.points??0)+' pts'));
   }
 if(s.distribution?.length){const total=Math.max(1,...s.distribution.map(v=>v[1]));
    if(q.type==='cloud'){const cloud=el('div',undefined,'cloud');for(const [w,n] of s.distribution){const span=el('span',w+' ×'+n);span.style.fontSize=(1+n/total)+'rem';cloud.append(span);}box.append(cloud);}
    else{for(const [w,n] of s.distribution){const item=el('div',w+' · '+n,'option'),bar=el('div',undefined,'bar');bar.style.width=(100*n/total)+'%';item.append(bar);box.append(item);}}}
}
function tick(){const t=$('timer');if(t&&state)t.textContent=state.phase==='open'?Math.max(0,Math.ceil((deadline-performance.now())/1000))+' s':(['paused','closed'].includes(state.phase)?publicNames[state.phase]:'');}
function responseForm(box,q,idx){
 const f=el('form'),area=el('div',undefined,'options');let get;const opts=q.options||[];
 if(['choice','multiple','poll','scale'].includes(q.type)){
  const many=q.type==='multiple',values=q.type==='scale'?['1','2','3','4','5']:opts;
  const controls=values.map((v,i)=>{const c=input(many?'checkbox':'radio',v);c.name='pick';c.id='ans'+i;
   const l=el('label',undefined,'check');l.append(c,document.createTextNode(v));area.append(l);return c;});
  get=()=>{const out=controls.filter(v=>v.checked).map(v=>v.value);return many?out:q.type==='scale'?Number(out[0]):out[0];};
 }else if(q.type==='order'){
  const order=opts.slice();const renderOrder=()=>{clear(area);order.forEach((v,i)=>{const line=el('div',undefined,'line'),buttons=el('div',undefined,'toolbar');
   function move(n){[order[i],order[n]]=[order[n],order[i]];renderOrder();}
   const up=btn('↑',()=>move(i-1)),down=btn('↓',()=>move(i+1));up.disabled=i===0;down.disabled=i===order.length-1;up.setAttribute('aria-label','Move '+v+' up');down.setAttribute('aria-label','Move '+v+' down');buttons.append(up,down);line.append(el('span',(i+1)+'. '+v),buttons);area.append(line);});};renderOrder();get=()=>order;
 }else if(['match','category'].includes(q.type)){const controls=q.labels.map(l=>{const c=select([['','Choose…'],...opts.map(v=>[v,v])]);c.required=true;area.append(field(l,c));return c;});get=()=>controls.map(c=>c.value);
 }else{const c=input(q.type==='number'?'number':'text','');c.required=true;c.maxLength=q.type==='cloud'?48:180;if(q.type==='number')c.step='any';area.append(field('Your answer',c));get=()=>q.type==='number'?c.valueAsNumber:c.value;}
 const b=el('button','Submit answer','primary');b.type='submit';f.append(area,b);
 f.onsubmit=async e=>{e.preventDefault();b.disabled=true;try{await api('/api/answer',{round:idx,value:get()});$('error').hidden=true;await refresh();}catch(err){fail(err);b.disabled=false;}};
 box.append(f);
}
function ranking(box,s){for(const [title,rows] of [['Teams',s.team_leaders],['Players',s.leaders]]){
 if(!rows?.length)continue;box.append(el('h3',title));for(const r of rows){const line=el('div',undefined,'score');line.append(el('span','#'+r.rank),el('span',r.name),el('b',String(r.score)));box.append(line);}}}
function side(s){const dest=$('side');clear(dest);
 if(mode!=='player'){const entry=el('section'),url=el('a',s.join_url,'joinUrl');url.href=s.join_url;url.target='_blank';url.rel='noopener';
 const qr=el('img');qr.className='qr';qr.src='/join.svg';qr.alt='QR code to join this contest';entry.append(el('h3','Join the room'),qr,url,message(s.players+' joined · '+(s.locked?'joining closed':'joining open')));dest.append(entry);}
 if(mode==='player'&&s.me){const card=el('section');card.append(el('h3',s.me.name),message(s.me.team||'Individual standings'));dest.append(card);}
 if(mode!=='host')return;
 const h=el('section'),buttons=el('div',undefined,'toolbar');h.append(el('h3','Host controls'),buttons);
 if(s.phase==='lobby'){buttons.append(btn('Start contest',()=>action('next'),'primary'),btn('Edit contest',()=>editor(s.deck)));}
 if(s.phase==='open')buttons.append(btn('Pause',()=>action('pause')));
 if(s.phase==='paused')buttons.append(btn('Resume',()=>action('resume'),'primary'));
 if(['open','paused','closed'].includes(s.phase))buttons.append(btn('Reveal answer',()=>action('reveal'),'primary'));
 if(s.phase==='reveal')buttons.append(btn('Show standings',()=>action('standings')));
 if(s.phase==='practice')buttons.append(btn('Finish contest',()=>{if(confirm('Close self-paced entries and show final standings?'))return action('finish');}));
 if(['reveal','standings'].includes(s.phase)){
  if(s.index+1<s.rounds)buttons.append(btn('Next round',()=>action('next'),'primary'));
  buttons.append(btn('Finish contest',()=>{if(confirm('Finish this contest and close entries?'))return action('finish');}));}
 if(s.phase!=='finished')buttons.append(btn(s.locked?'Open joining':'Lock joining',()=>action('lock')));
 buttons.append(btn('Projector view',()=>window.open(s.audience_url,'_blank','noopener')),btn('Export results',exportCSV));dest.prepend(h);
}
async function exportCSV(){const r=await fetch('/api/host/results',{headers:{Authorization:'Bearer '+token}});if(!r.ok)throw new Error('Could not export results.');saveBlob(await r.blob(),'contest-results.csv');}
function saveBlob(blob,name){const a=el('a');a.href=URL.createObjectURL(blob);a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),3000);}
function discussion(s){$('discussion').hidden=mode==='display'&&!s.qa.length;
 if(mode==='player'&&s.phase!=='finished'&&!$('ask').childElementCount){
  const f=el('form'),i=input('text','');i.maxLength=240;i.required=true;const b=el('button','Send question');b.type='submit';f.append(field('Ask the host',i),b);
  f.onsubmit=async e=>{e.preventDefault();try{await api('/api/ask',{text:i.value});i.value='';i.placeholder='Sent for moderation';}catch(err){fail(err);}};$('ask').append(f);}
 if(s.phase==='finished')clear($('ask'));const msgs=$('messages');clear(msgs);
 for(const q of s.qa){const r=el('div',undefined,'qaRow');r.append(el('strong',q.body),message(q.status+' · '+q.votes+' votes'));const t=el('div',undefined,'toolbar');
 if(mode==='host')for(const [status,title] of [['published','Publish'],['hidden','Hide'],['answered','Mark answered']]){if(q.status!==status)t.append(btn(title,async()=>{await api('/api/host/moderate',{id:q.id,status});await refresh();}));}
 if(mode==='player'&&q.status==='published'&&s.phase!=='finished')t.append(btn('Upvote',async()=>{await api('/api/vote',{id:q.id});await refresh();}));
 r.append(t);msgs.append(r);}
}
function editor(deck){editing=JSON.parse(JSON.stringify(deck));editIndex=0;$('editError').textContent='';drawEditor();$('editor').showModal();}
function lines(s){return s.split('\n').map(x=>x.trim()).filter(Boolean);}
function area(value){const t=el('textarea');t.value=Array.isArray(value)?value.join('\n'):(value??'');return t;}
function drawEditor(){
 const box=$('editBody'),q=editing.questions[editIndex];clear(box);
 function connect(e,handler){e.addEventListener('input',handler);return e;}
 const title=input('text',editing.title);box.append(field('Contest title',connect(title,()=>editing.title=title.value)));
 const teams=area(editing.teams);box.append(field('Team names · one per line, or leave empty for individual play',connect(teams,()=>editing.teams=lines(teams.value))));
 const speed=input('checkbox','');speed.checked=editing.speed_bonus;const sp=el('label',undefined,'check');sp.append(connect(speed,()=>editing.speed_bonus=speed.checked),document.createTextNode('Award a speed bonus for correct answers'));box.append(sp);
 const tools=el('div',undefined,'toolbar'),jump=select(editing.questions.map((x,i)=>[String(i),String(i+1)+'. '+x.prompt.slice(0,48)]),String(editIndex));jump.onchange=()=>{editIndex=Number(jump.value);drawEditor();};box.append(field('Round',jump));
 tools.append(btn('Add round',()=>{editing.questions.splice(editIndex+1,0,{type:'choice',prompt:'New question',options:['First option','Second option'],answer:'First option',seconds:30,points:1000});editIndex++;drawEditor();}));
 if(editing.questions.length>1)tools.append(btn('Delete round',()=>{editing.questions.splice(editIndex,1);editIndex=Math.min(editIndex,editing.questions.length-1);drawEditor();}));
 for(const [delta,label] of [[-1,'Move earlier'],[1,'Move later']]){const n=editIndex+delta;if(n>=0&&n<editing.questions.length)tools.append(btn(label,()=>{[editing.questions[n],editing.questions[editIndex]]=[editing.questions[editIndex],editing.questions[n]];editIndex=n;drawEditor();}));}
 box.append(tools);
 const type=select(Object.entries(names),q.type);type.onchange=()=>{q.type=type.value;delete q.answer;drawEditor();};box.append(field('Round type',type));
 const prompt=area(q.prompt);box.append(field('Question or slide text',connect(prompt,()=>q.prompt=prompt.value)));
 const pair=el('div',undefined,'editGroups'),secs=input('number',q.seconds),points=input('number',q.points);secs.min=3;secs.max=600;points.min=0;points.max=10000;
 pair.append(field('Seconds',connect(secs,()=>q.seconds=Number(secs.value))),field('Maximum points',connect(points,()=>q.points=Number(points.value))));box.append(pair);
 const hasOpts=['choice','multiple','order','match','category','poll'].includes(q.type);
 if(hasOpts){const opts=area(q.options);box.append(field('Choices in display order · one per line',connect(opts,()=>q.options=lines(opts.value))));}
 if(['match','category'].includes(q.type)){const labels=area(q.labels);box.append(field('Left-hand items · one per line',connect(labels,()=>q.labels=lines(labels.value))));}
 if(!['scale','poll','cloud','slide'].includes(q.type)){
  const labels={choice:'Correct choice',multiple:'All correct choices · one per line',order:'Correct sequence · one choice per line',match:'Correct choice for each left-hand item · one per line',category:'Category for each item · one per line',text:'Accepted spellings · one per line',number:'Correct numerical value'};
  const ans=area(q.answer);box.append(field(labels[q.type],connect(ans,()=>q.answer=q.type==='number'?Number(ans.value):q.type==='choice'?ans.value.trim():lines(ans.value))));
  if(q.type==='number'){const tol=input('number',q.tolerance??0);tol.min=0;tol.step='any';box.append(field('Absolute tolerance',connect(tol,()=>q.tolerance=Number(tol.value))));}}
 if(['poll','cloud','scale'].includes(q.type)){const live=input('checkbox','');live.checked=q.live_results??(q.type!=='cloud');const l=el('label',undefined,'check');l.append(connect(live,()=>q.live_results=live.checked),document.createTextNode('Show incoming responses live'));box.append(l);}
 const why=area(q.explanation);box.append(field('Explanation after reveal',connect(why,()=>q.explanation=why.value)));
 const pic=input('file','');pic.accept='image/png,image/jpeg';pic.onchange=async()=>{const f=pic.files[0];if(!f)return;if(f.size>524288){$('editError').textContent='Use an image under 512 KiB.';return;}const reader=new FileReader();reader.onload=()=>{q.image=reader.result;drawEditor();};reader.readAsDataURL(f);};
 box.append(field('Question image · local PNG or JPEG',pic));if(q.image){const im=el('img');im.className='questionImage';im.src=q.image;im.alt='Current illustration';box.append(im,btn('Remove image',()=>{delete q.image;drawEditor();}));}
}
$('dismiss').onclick=()=>$('editor').close();
$('editForm').onsubmit=async e=>{e.preventDefault();try{await action('deck',{deck:editing});$('editor').close();lastSide='';await refresh();}catch(err){$('editError').textContent=err.message;}};
$('exportDeck').onclick=()=>saveBlob(new Blob([JSON.stringify(editing,null,2)],{type:'application/json'}),'contest.quiz.json');
$('importDeck').onchange=async e=>{try{const file=e.target.files[0];if(!file||file.size>8*1024*1024)throw new Error('Select a quiz deck smaller than 8 MiB.');let d;if(/\.(pptx|pdf)$/i.test(file.name)){
 const reader=new FileReader();const uri=await new Promise((ok,no)=>{reader.onload=()=>ok(reader.result);reader.onerror=()=>no(new Error('File could not be read.'));reader.readAsDataURL(file);});
 d=await api('/api/host/import',{file:uri.split(',')[1],name:file.name});}else{d=JSON.parse(await file.text());}if(d.format!=='oes-quiz'||!Array.isArray(d.questions)||!d.questions.length||!Array.isArray(d.teams))throw new Error('Invalid quiz deck.');editing=d;editIndex=0;drawEditor();}catch(err){$('editError').textContent=err.message;}};
refresh();setInterval(refresh,1000);setInterval(tick,200);
