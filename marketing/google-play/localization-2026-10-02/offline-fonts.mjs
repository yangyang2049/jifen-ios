// Resolve Pen's optional Google-font bootstrap and fallback downloads using
// bundled OFL fonts. All non-font account/API/network requests are unchanged.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const normal=globalThis.fetch;
const root=path.join(path.dirname(fileURLToPath(import.meta.url)),'fonts');
globalThis.fetch=async function(input,options){
 const url=String(input?.url??input);
 const match=url.match(/^https:\/\/fonts\.gstatic\.com\/s\/([^/]+)\//);
 if(match){
  let family=match[1];
  if(family==='notosanstc'||family==='notosanssc')family='notosansjp';
  const folder=path.join(root,family);
  if(fs.existsSync(folder)){
   const font=fs.readdirSync(folder).find(x=>x.endsWith('.ttf')&&!x.includes('Italic'));
   if(font){process.stderr.write('[FONT] Local bootstrap/fallback: '+family+'\n');return new Response(fs.readFileSync(path.join(folder,font)),{status:200,headers:{'Content-Type':'font/ttf'}});}
  }
  process.stderr.write('[FONT] Unbundled fallback request: '+match[1]+'\n');
 }
 return normal(input,options);
};
