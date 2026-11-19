if (window.Blockly) {
  const B=window.Blockly;
  const types=[["oes_analog","analog input",["A0","A1","A2","A3","A4","A5"],"dial"],["oes_button","push button",Array.from({length:11},(_,i)=>String(i+2)),"button"]];
  B.defineBlocksWithJsonArray(types.map(([type,title,pins,channel])=>({type,message0:title+" %1 → channel %2",args0:[{type:"field_dropdown",name:"PIN",options:pins.map(p=>[p,p])},{type:"field_input",name:"CHANNEL",text:channel}],colour:185,previousStatement:null,nextStatement:null})));
  const ws=B.inject("workspace",{media:"node_modules/blockly/media/",toolbox:{kind:"flyoutToolbox",contents:types.map(([type])=>({kind:"block",type}))},trashcan:true});
  function refresh(){
    const ordered=[];
    for(const top of ws.getTopBlocks(true))for(let b=top;b;b=b.getNextBlock())ordered.push({type:b.type,pin:b.getFieldValue("PIN"),channel:b.getFieldValue("CHANNEL")});
    try{document.getElementById("code").textContent=generateExhibitSketch(ordered);document.getElementById("save").disabled=false;document.getElementById("status").textContent="USB serial · 115200 baud · one sample per channel every 100 ms.";}
    catch(err){document.getElementById("status").textContent=err.message;document.getElementById("save").disabled=true;}
  }
  const block=ws.newBlock("oes_analog");block.initSvg();block.render();block.moveBy(30,35);
  ws.addChangeListener(refresh);refresh();
  document.getElementById("save").onclick=()=>{const url=URL.createObjectURL(new Blob([document.getElementById("code").textContent],{type:"text/plain"}));const a=document.createElement("a");a.href=url;a.download="ExhibitInputs.ino";a.click();setTimeout(()=>URL.revokeObjectURL(url),3000);};
}
