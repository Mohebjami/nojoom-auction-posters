const http=require('node:http');
const {timingSafeEqual}=require('node:crypto');
function authorized(value,token) {
  const actual=Buffer.from(value || ''); const expected=Buffer.from(`Bearer ${token}`);
  return actual.length===expected.length && timingSafeEqual(actual,expected);
}
async function createAPI({token,getState,command,posterPhotos}) {
  const server=http.createServer(async(req,res)=>{
    res.setHeader('Content-Type','application/json');
    res.setHeader('Cache-Control','no-store');
    const send=(code,value)=>{res.writeHead(code);res.end(JSON.stringify(value));};
    // No browser origins or CORS. Only the native client knows the random token.
    if(req.headers.origin || !authorized(req.headers.authorization,token)) return send(403,{error:'Forbidden'});
    try {
      if(req.method==='GET' && req.url==='/state') return send(200,getState());
      if(req.method!=='POST' || req.url!=='/command') return send(404,{error:'Not found'});
      let size=0; const chunks=[];
      for await(const chunk of req) {size+=chunk.length;if(size>16384) return send(413,{error:'Request too large'});chunks.push(chunk);}
      const body=JSON.parse(Buffer.concat(chunks).toString());
      if(typeof body.action!=='string') throw new Error('Missing action.');
      const result=body.action==='poster-photos'?await posterPhotos(body.args?.id):await command(body.action,body.args || {});
      send(200,result ?? getState());
    } catch(error) {send(400,{error:error.message});}
  });
  server.requestTimeout=150000;
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  return server;
}
module.exports={createAPI};
