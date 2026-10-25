/** A deliberately closed GDScript computational subset. No engine, eval or I/O.
 * The IR retains ordered statements, aliasing and lazy control flow. Backends
 * must specialize finite containers; unsupported reachable code is an error.
 *
 * compileModel(source, {entrypoints?, maxRangeLength?}) returns serializable IR.
 * Defaults compile the maintained initial/transition/benchmark/portfolio graph.
 * evaluateModel(IR, name, positionalArguments, {inputs:{portfolio}}) is a pure
 * interpreter, not a native-model qualification. No source text is eval'd.
 * The only admitted I/O boundary forwards supplied portfolio data through the
 * canonical validator; changing that wrapper's non-I/O behavior is rejected.
 */
import { createHash } from 'node:crypto';

export const COMPILER_VERSION = 'gd-model-ir-12';
export class ModelCompileError extends Error {
  constructor(message, at) { super(`${at ? `L${at.line}:${at.column}: ` : ''}${message}`); this.name = 'ModelCompileError'; this.source = at; }
}
const fail = (message, at) => { throw new ModelCompileError(message, at); };
const hash = text => createHash('sha256').update(text).digest('hex');
// Preserve every own String data key, including __proto__. Ordinary assignment
// on a fresh {} would invoke the inherited prototype setter instead of storing
// that legal Dictionary key. Public dictionaries remain ordinary JS objects.
const setOwn=(target,key,value)=>{Object.defineProperty(target,key,{value,writable:true,enumerable:true,configurable:true});return value;};
// Source Dictionary order is independent of JavaScript's index-key ordering.
// A sidecar keeps ordinary own-key public records (including __proto__) and
// preserves source order internally without changing JSON/value interfaces.
// Raw external JS index-key order is irretrievable: lookups remain valid, but
// order-observing operations refuse instead of guessing the original order.
const dictionaryOrders=new WeakMap();
const indexKey=key=>/^(0|[1-9][0-9]*)$/.test(key)&&Number(key)<4294967295;
const dictionaryKeys=(value,observe=false)=>{
  const info=dictionaryOrders.get(value),keys=Object.keys(value);
  if(info&&(keys.length!==info.keys.length||info.keys.some(k=>!Object.hasOwn(value,k))))throw new TypeError('ordered Dictionary was structurally changed outside the interpreter');
  if(observe&&(info?.unknown??keys.some(indexKey)))throw new TypeError('external Dictionary insertion order is unproved for numeric-looking String keys');
  return info?info.keys.slice():keys;
};
// Code-owned bridge for source-created constants passed to the emitter. It
// exposes entries/proof data only, never callbacks or caller-selected schemas.
export function dictionaryEntries(value){
  // Only code-owned, recursively frozen constant records may carry an ordering
  // proof across this public bridge. Mutable external data is re-admitted from
  // its actual own properties, never from an old sidecar history.
  const info=Object.isFrozen(value)?dictionaryOrders.get(value):undefined,keys=info?dictionaryKeys(value):Object.keys(value);
  return {entries:keys.map(k=>[k,value[k]]),orderProved:!(info?.unknown??keys.some(indexKey))};
}
const dictionarySet=(value,key,item)=>{const info=dictionaryOrders.get(value);if(info&&!Object.hasOwn(value,key))info.keys.push(key);return setOwn(value,key,item);};
const dictionary=(entries=[],unknown=false)=>{const result={};dictionaryOrders.set(result,{keys:[],unknown});for(const [key,value]of entries)dictionarySet(result,key,value);return result;};
export function irFingerprint(ir){const {irSha256,...body}=ir;return hash(JSON.stringify(body,(_,v)=>typeof v==='number'&&!Number.isFinite(v)?{$number:String(v)}:v));}
const TYPES = new Set(['Variant', 'float', 'int', 'bool', 'String', 'Array', 'Dictionary', 'void']);
const BUILTINS = new Set(['float','int','str','typeof','is_finite','pow','abs','min','max','minf','maxf','clamp','exp','log','tanh','lerpf','round','roundf','signf','floor','range']);
const METHODS = new Set(['get','has','size','duplicate','slice','append','append_array','fill','resize','pop_front','pop_back','sort','is_empty','merge','values','keys','is_valid_float']);
const ARITY={float:[1,1],int:[1,1],str:[1,1],typeof:[1,1],is_finite:[1,1],pow:[2,2],abs:[1,1],min:[2,Infinity],max:[2,Infinity],minf:[2,2],maxf:[2,2],clamp:[3,3],exp:[1,1],log:[1,1],tanh:[1,1],lerpf:[3,3],round:[1,1],roundf:[1,1],signf:[1,1],floor:[1,1],range:[1,3]};
const METHOD_ARITY={get:[1,2],has:[1,1],size:[0,0],duplicate:[0,1],slice:[1,2],append:[1,1],append_array:[1,1],fill:[1,1],resize:[1,1],pop_front:[0,0],pop_back:[0,0],sort:[0,0],is_empty:[0,0],merge:[1,2],values:[0,0],keys:[0,0],is_valid_float:[0,0]};
const METHOD_RECEIVERS={get:['array','dictionary'],has:['array','dictionary'],size:['array','dictionary'],duplicate:['array','dictionary'],is_empty:['array','dictionary'],slice:['array'],append:['array'],append_array:['array'],fill:['array'],resize:['array'],pop_front:['array'],pop_back:['array'],sort:['array'],merge:['dictionary'],values:['dictionary'],keys:['dictionary'],is_valid_float:['string']};
// Source-visible Godot Variant.Type values, NOT the internal gdType categories.
// Only the represented scalar/container types are admitted by this subset.
export const VARIANT_TYPES=Object.freeze({TYPE_NIL:0,TYPE_BOOL:1,TYPE_INT:2,TYPE_FLOAT:3,TYPE_STRING:4,TYPE_DICTIONARY:27,TYPE_ARRAY:28});
const PREDEFINED = { true:true, false:false, null:null, INF:Infinity, NAN:NaN,...VARIANT_TYPES };

function lex(source) {
  const tokens = [], indents = [0]; let i=0, line=1, column=1, start=true, depth=0, continued=false;
  const push = (kind, value=kind, at={line,column,offset:i}) => tokens.push({kind,value,...at});
  const move = () => { const c=source[i++]; if(c==='\n'){line++;column=1;start=true;}else column++; return c; };
  while(i<source.length) {
    if(start) {
      let indent=0; while(source[i]===' '||source[i]==='\t'){indent+=source[i]==='\t'?4:1;move();}
      start=false;
      if(source[i]==='#'||source[i]==='\n'||source[i]==='\r'||i>=source.length) { /* blank lines do not dedent */ }
      else if(depth===0&&!continued) {
        if(indent>indents.at(-1)){indents.push(indent);push('INDENT');}
        while(indent<indents.at(-1)){indents.pop();push('DEDENT');}
        if(indent!==indents.at(-1)) fail('inconsistent indentation',{line,column});
      }
      continued=false;
    }
    const c=source[i], at={line,column,offset:i};
    if(c===' '||c==='\t'||c==='\r'){move();continue;}
    if(c==='#'){while(i<source.length&&source[i]!=='\n')move();continue;}
    if(c==='\\'&&source[i+1]==='\n'){move();move();continued=true;continue;}
    if(c==='\n'){move();if(depth===0)push('NEWLINE','NEWLINE',at);continue;}
    if(c==='"'||c==="'") {
      const quote=move();let value='',closed=false;
      while(i<source.length){const x=move();if(x===quote){closed=true;break;}if(x==='\\'){const e=move();value+=({n:'\n',r:'\r',t:'\t','\\':'\\','"':'"',"'":"'"})[e]??fail(`unsupported escape \\${e}`,at);}else{if(x==='\n')fail('multiline strings unsupported',at);value+=x;}}
      if(!closed)fail('unterminated string',at);push('string',value,at);continue;
    }
    // Separators are admitted only between digits. Hex E/e is a digit, never a
    // decimal exponent marker; keep the lexical spelling until classification.
    const number=source.slice(i).match(/^(?:0x[0-9a-fA-F](?:_?[0-9a-fA-F])*|(?:\d(?:_?\d)*(?:\.(?:\d(?:_?\d)*)?)?|\.\d(?:_?\d)*)(?:[eE][+-]?\d(?:_?\d)*)?)/);
    if(number){for(let n=0;n<number[0].length;n++)move();push('number',number[0],at);continue;}
    const name=source.slice(i).match(/^[A-Za-z_][A-Za-z_0-9]*/);
    if(name){for(let n=0;n<name[0].length;n++)move();push('name',name[0],at);continue;}
    const op=[':=','->','==','!=','<=','>=','+=','-=','*=','/=','**'].find(x=>source.startsWith(x,i))??c;
    if(!'()[]{}.,:;+-*/%=<>^'.includes(op[0])&&![':=','->','!='].includes(op))fail(`unsupported token ${c}`,at);
    for(let n=0;n<op.length;n++)move();
    if('([{'.includes(op))depth++;
    if(')]}'.includes(op)){depth--;if(depth<0)fail('unbalanced delimiter',at);}
    push(op,op,at);
  }
  if(depth)fail('unclosed delimiter',{line,column});
  push('NEWLINE');while(indents.length>1){indents.pop();push('DEDENT');}push('EOF');return tokens;
}

class Parser {
  constructor(source){this.tokens=lex(source);this.index=0;}
  get t(){return this.tokens[this.index];}
  is(value){return this.t.kind===value||this.t.value===value;}
  take(value){if(value&&!this.is(value))fail(`expected ${value}, got ${this.t.value}`,this.t);return this.tokens[this.index++];}
  maybe(value){if(this.is(value))return this.take();return null;}
  node(kind,at,fields={}){return {kind,source:{line:at.line,column:at.column,offset:at.offset},...fields};}
  lines(){while(this.maybe('NEWLINE'));}
  type(){const t=this.take('name');if(!TYPES.has(t.value))fail(`unsupported type ${t.value}`,t);return t.value;}
  module(){
    const functions=Object.create(null),constants=[];this.lines();
    while(!this.is('EOF')){
      if(this.maybe('extends')){this.take('name');this.take('NEWLINE');}
      else if(this.is('const'))constants.push(this.declaration(true));
      else {this.maybe('static');const at=this.take('func'),name=this.take('name').value;this.take('(');const params=[];
        while(!this.is(')')){const p=this.take('name'),type=this.maybe(':')?this.type():'Variant';const value=this.maybe('=')?this.expression():null;params.push({name:p.value,type,value,source:p});if(!this.maybe(','))break;}
        this.take(')');const returns=this.maybe('->')?this.type():'Variant';this.take(':');
        if(Object.hasOwn(functions,name))fail(`duplicate function ${name}`,at);
        functions[name]=this.node('function',at,{name,params,returns,body:this.block()});
      }this.lines();
    }return {functions,constants};
  }
  declaration(constant=false){const at=this.take(constant?'const':'var'),name=this.take('name').value;let type='Variant';
    if(this.maybe(':'))type=this.type();
    const assigned=this.maybe(':=')||this.maybe('=');const value=assigned?this.expression():null;
    if(constant&&!assigned)fail('constant requires a value',at);this.end();return this.node('declare',at,{name,type,value,constant,inferred:assigned?.value===':='});}
  end(){if(!this.maybe(';'))this.take('NEWLINE');}
  block(){this.take('NEWLINE');this.lines();this.take('INDENT');const body=[];this.lines();while(!this.is('DEDENT')&&!this.is('EOF')){body.push(this.statement());this.lines();}this.take('DEDENT');return body;}
  statement(){const at=this.t;
    if(this.is('var'))return this.declaration();
    if(this.maybe('return')){const value=this.is('NEWLINE')?this.node('literal',at,{value:null,type:'null'}):this.expression();this.end();return this.node('return',at,{value});}
    if(this.maybe('if'))return this.conditional(at);
    if(this.maybe('for')){const name=this.take('name').value;this.take('in');const iterable=this.expression();this.take(':');return this.node('for',at,{name,iterable,body:this.block()});}
    if(this.maybe('while')){const condition=this.expression();this.take(':');return this.node('while',at,{condition,body:this.block()});}
    if(this.maybe('break')||this.maybe('continue')||this.maybe('pass')){this.end();return this.node(at.value,at);}
    const target=this.expression();
    if(['=','+=','-=','*=','/='].some(x=>this.is(x))){const op=this.take().value,value=this.expression();this.end();return this.node('assign',at,{target,op,value});}
    this.end();return this.node('expression',at,{value:target});
  }
  conditional(at){const condition=this.expression();this.take(':');const yes=this.block();this.lines();let no=[];
    if(this.maybe('elif'))no=[this.conditional(this.tokens[this.index-1])];else if(this.maybe('else')){this.take(':');no=this.block();}
    return this.node('if',at,{condition,yes,no});}
  expression(min=0){let left=this.prefix();
    for(;;){
      if(this.is('(')){if(90<min)break;const at=this.take(),args=[];while(!this.is(')')){args.push(this.expression());if(!this.maybe(','))break;}this.take(')');left=this.node('call',at,{callee:left,args});continue;}
      if(this.is('.')){if(90<min)break;const at=this.take(),name=this.take('name').value;left=this.node('member',at,{object:left,name});continue;}
      if(this.is('[')){if(90<min)break;const at=this.take(),index=this.expression();this.take(']');left=this.node('index',at,{object:left,index});continue;}
      if(this.is('if')&&min<=5){const at=this.take(),condition=this.expression(6);this.take('else');left=this.node('conditional',at,{condition,yes:left,no:this.expression(5)});continue;}
      let op=this.t.value;
      if(op==='not'&&this.tokens[this.index+1].value==='in')op='not in';
      const prec=({or:10,and:20,in:30,'not in':30,is:30,'==':30,'!=':30,'<':30,'>':30,'<=':30,'>=':30,'^':35,'+':40,'-':40,'*':50,'/':50,'%':50,'**':60})[op];
      if(prec===undefined||prec<min)break;const at=this.take();if(op==='not in')this.take('in');const right=this.expression(prec+(op==='**'?0:1));left=this.node('binary',at,{op,left,right});
    }return left;
  }
  prefix(){const at=this.take();
    if(at.kind==='number')return this.node('literal',at,{value:Number(at.value.replaceAll('_','')),type:at.value.startsWith('0x')?'int':/[.eE]/.test(at.value)?'float':'int'});
    if(at.kind==='string')return this.node('literal',at,{value:at.value,type:'String'});
    if(at.value==='not'||at.value==='-'||at.value==='+')return this.node('unary',at,{op:at.value,value:this.expression(at.value==='not'?25:55)});
    if(at.value==='('){const v=this.expression();this.take(')');return v;}
    if(at.value==='['){const items=[];while(!this.is(']')){items.push(this.expression());if(!this.maybe(','))break;}this.take(']');return this.node('array',at,{items});}
    if(at.value==='{'){const entries=[];while(!this.is('}')){const key=this.expression();this.take(':');const value=this.expression();entries.push({key,value});if(!this.maybe(','))break;}this.take('}');return this.node('dictionary',at,{entries});}
    if(at.kind==='name')return this.node('name',at,{name:at.value});
    fail(`unsupported expression ${at.value}`,at);
  }
}

export function walkIR(node,visit){if(!node||typeof node!=='object')return;if(node.kind)visit(node);for(const [key,value] of Object.entries(node)){if(key==='source'||key==='proof')continue;if(Array.isArray(value))value.forEach(x=>walkIR(x,visit));else if(value&&typeof value==='object')walkIR(value,visit);}}

// A structural ranking proof, not a financial-function exception. Every path
// must decrease the sum of the guarded array lengths; unknown effects reject.
function decreasingArrayProof(loop){
  const arrays=[];
  const guard=n=>{if(n.kind==='binary'&&n.op==='and')return guard(n.left)&&guard(n.right);
    if(n.kind==='unary'&&n.op==='not'&&n.value.kind==='call'&&n.value.args.length===0&&n.value.callee.kind==='member'&&n.value.callee.name==='is_empty'&&n.value.callee.object.kind==='name'){arrays.push(n.value.callee.object.name);return true;}return false;};
  if(!guard(loop.condition)||!arrays.length||new Set(arrays).size!==arrays.length)return null;
  let valid=true;
  const union=(...paths)=>[...new Set(paths.flat())],sum=(a,b)=>union(a.flatMap(x=>b.map(y=>x+y)));
  // Closed effect system: no helper call (including transitive alias mutation)
  // is assumed pure. Lazy expressions include BOTH taken and skipped paths.
  // Bare ranking references cannot escape through an alias/container argument.
  const effect=n=>{
    if(!n)return [0];
    if(n.kind==='literal')return [0];
    if(n.kind==='name'){if(arrays.includes(n.name))valid=false;return [0];}
    if(n.kind==='conditional'){const condition=effect(n.condition);if(condition.some(x=>x!==0))valid=false;return sum(condition,union(effect(n.yes),effect(n.no)));}
    if(n.kind==='binary'){const a=effect(n.left),b=effect(n.right);return sum(a,['and','or'].includes(n.op)?union([0],b):b);}
    if(n.kind==='call'){
      const c=n.callee;
      if(c.kind==='member'&&c.object.kind==='name'&&arrays.includes(c.object.name)&&((c.name==='pop_back'&&n.args.length===0)||(c.name==='append'&&n.args.length===1))){
        const args=n.args.reduce((a,x)=>sum(a,effect(x)),[0]);return sum(args,[c.name==='pop_back'?-1:1]);
      }
      // Pure numeric builtins are closed; arbitrary user helpers are not.
      if(c.kind==='name'&&BUILTINS.has(c.name))return n.args.reduce((a,x)=>sum(a,effect(x)),[0]);
      valid=false;return [0];
    }
    if(n.kind==='unary')return effect(n.value);
    if(n.kind==='member')return effect(n.object);
    if(n.kind==='index')return sum(effect(n.object),effect(n.index));
    if(n.kind==='array')return n.items.reduce((a,x)=>sum(a,effect(x)),[0]);
    if(n.kind==='dictionary')return n.entries.reduce((a,x)=>sum(a,sum(effect(x.key),effect(x.value))),[0]);
    valid=false;return [0];
  };
  const effects=body=>{let paths=[0];for(const s of body){
      if(s.kind==='if'){const condition=effect(s.condition);if(condition.some(x=>x!==0))valid=false;paths=sum(paths,sum(condition,union(effects(s.yes),effects(s.no))));continue;}
      if(!['declare','expression','pass'].includes(s.kind)){valid=false;continue;}
      if(s.kind==='declare'&&arrays.includes(s.name))valid=false;
      paths=sum(paths,effect(s.value));
    }return paths;};
  const deltas=effects(loop.body);
  return valid&&deltas.every(d=>d<0)?{kind:'decreasing-array-length',arrays,maximumDelta:Math.max(...deltas)}:null;
}

export function compileModel(source,inputSchema={}){
  if(typeof source!=='string')throw new TypeError('compileModel requires canonical source text');
  const parsed=new Parser(source).module();
  const entrypoints=inputSchema.entrypoints??['initial_state','step','benchmark_policy','_validate_portfolio_reference'];
  const boundaries=inputSchema.boundaries??(parsed.functions.load_portfolio_reference?{
    load_portfolio_reference:{input:'portfolio',validator:'_validate_portfolio_reference'}
  }:{});
  for(const [name,spec] of Object.entries(boundaries)){
    if(name!=='load_portfolio_reference')fail(`input boundary ${name} is not an admitted input-only I/O function`);
    if(!spec.input||!spec.validator||!parsed.functions[spec.validator])fail(`boundary ${name} requires a named input and canonical validator`);
    const fn=parsed.functions[name],body=fn?.body??[],first=body[0],check=body[1],validation=body[2],last=body[3];
    const named=(x,name)=>x?.kind==='name'&&x.name===name;
    const member=(x,base,name)=>x?.kind==='member'&&named(x.object,base)&&x.name===name;
    if(spec.validator!=='_validate_portfolio_reference'||body.length!==4||first?.kind!=='declare'||first.value?.kind!=='call'||!named(first.value.callee,'_read_json')||first.value.args.length!==1||!named(first.value.args[0],fn.params[0]?.name)
      ||check?.kind!=='if'||check.condition?.kind!=='unary'||check.condition.op!=='not'||!member(check.condition.value,first.name,'ok')||check.yes.length!==1||check.no.length!==0||check.yes[0].kind!=='return'||!named(check.yes[0].value,first.name)
      ||validation?.kind!=='declare'||validation.value?.kind!=='call'||!named(validation.value.callee,spec.validator)||validation.value.args.length!==1||!member(validation.value.args[0],first.name,'value')
      ||last?.kind!=='return'||last.value?.kind!=='conditional'||!member(last.value.condition,validation.name,'ok')||!named(last.value.yes,first.name)||!named(last.value.no,validation.name))fail(`input boundary ${name} changed: only raw input + canonical validation + unchanged forwarding is admitted`,fn?.source);
  }
  const functions=Object.create(null),pending=[...entrypoints],usedBoundaries=new Set();
  while(pending.length){const name=pending.pop();if(functions[name])continue;const fn=parsed.functions[name];if(!fn)fail(`unresolved entrypoint/dependency ${name}`);
    if(BUILTINS.has(name))fail(`function ${name} shadows a builtin outside the admitted subset`,fn.source);
    functions[name]=fn;
    walkIR(fn,n=>{
      if(n.kind==='literal'&&n.type==='int'&&!Number.isSafeInteger(n.value))fail('integer literal exceeds exact backend integer domain',n.source);
      if(n.kind==='literal'&&typeof n.value==='number'&&!Number.isFinite(n.value))fail('nonfinite literal must use the explicit canonical INF/NAN names',n.source);
      if(n.kind==='binary'&&n.op==='^')fail('unsupported reachable bitwise operator',n.source);
      if(n.kind==='call'){
        const c=n.callee;
        if(c.kind==='name'){
          if(Object.hasOwn(boundaries,c.name)){usedBoundaries.add(c.name);pending.push(boundaries[c.name].validator);return;}
          if(parsed.functions[c.name]){const f=parsed.functions[c.name],required=f.params.filter(p=>!p.value).length;if(n.args.length<required||n.args.length>f.params.length)fail(`argument count for ${c.name}`,n.source);pending.push(c.name);}else if(!BUILTINS.has(c.name))fail(`unresolved/unsupported call ${c.name}`,n.source);
          else if(n.args.length<ARITY[c.name][0]||n.args.length>ARITY[c.name][1])fail(`argument count for builtin ${c.name}`,n.source);
        }else if(c.kind==='member'){if(!METHODS.has(c.name))fail(`unsupported method ${c.name}`,n.source);const [min,max]=METHOD_ARITY[c.name];if(n.args.length<min||n.args.length>max)fail(`unsupported argument count for ${c.name}`,n.source);}else fail('dynamic call unsupported',n.source);
      }
      if(n.kind==='while'){n.proof=decreasingArrayProof(n);if(!n.proof)fail('while loop has no decreasing finite-container bound',n.source);}
      if(n.kind==='for'){
        if(n.iterable.kind==='call'&&n.iterable.callee.kind==='name'&&n.iterable.callee.name==='range'){
          const integer=x=>x.kind==='literal'&&Number.isSafeInteger(x.value)||x.kind==='unary'&&['+','-'].includes(x.op)&&integer(x.value);
          if(!n.iterable.args.every(integer))fail('range loop bound must be literal finite integers; editable/unproved range rejected',n.source);
          const value=x=>x.kind==='literal'?x.value:x.op==='-'?-value(x.value):value(x.value);
          try{builtinValue('range',n.iterable.args.map(value),inputSchema.maxRangeLength??10000);}catch(e){fail(e.message,n.source);}
        }
        n.proof={kind:'finite-container-specialization-required'};
      }
      if(n.kind==='assign'&&!['name','member','index'].includes(n.target.kind))fail('unsupported assignment target',n.source);
      if(['break','continue'].includes(n.kind))fail(`${n.kind} is outside the reachable computational subset`,n.source);
    });
  }
  const globalNames=new Set([...Object.keys(PREDEFINED),...parsed.constants.map(x=>x.name),...Object.keys(functions),...Object.keys(boundaries),...BUILTINS]);
  for(const fn of Object.values(functions)){
    const locals=new Set(fn.params.map(x=>x.name));walkIR(fn,n=>{if(n.kind==='declare'||n.kind==='for')locals.add(n.name);});
    walkIR(fn,n=>{if(n.kind==='name'&&!locals.has(n.name)&&!globalNames.has(n.name))fail(`unresolved variable ${n.name}`,n.source);});
  }
  // Recursive functions cannot be silently expanded by either backend.
  const active=new Set(),done=new Set();const visit=name=>{if(active.has(name))fail(`recursive dependency ${name}`,functions[name].source);if(done.has(name))return;active.add(name);
    walkIR(functions[name],n=>{if(n.kind==='call'&&n.callee.kind==='name'&&functions[n.callee.name])visit(n.callee.name);});active.delete(name);done.add(name);};Object.keys(functions).forEach(visit);
  let sequence=0;const locations=[];
  for(const fn of Object.values(functions))walkIR(fn,n=>{n.id=++sequence;locations.push({id:n.id,kind:n.kind,...n.source});});
  // Declared types are checked here; Variant stays a tagged runtime value. The
  // emitter specializes it against concrete finite input schemas, never guesses.
  const annotate=(node,env)=>{
    if(!node||typeof node!=='object')return 'Variant';
    if(node.kind==='name'){node.type=env[node.name]??'Variant';return node.type;}
    if(node.kind==='literal')return node.type;
    if(node.kind==='array')node.type='Array';else if(node.kind==='dictionary')node.type='Dictionary';
    else if(node.kind==='binary')node.type=['==','!=','<','>','<=','>=','in','not in','is','and','or'].includes(node.op)?'bool':'Variant';
    else if(node.kind==='unary')node.type=node.op==='not'?'bool':'Variant';
    else if(node.kind==='call')node.type=node.callee.kind==='name'?(functions[node.callee.name]?.returns??({float:'float',int:'int',typeof:'int',lerpf:'float',pow:'float',exp:'float',log:'float',tanh:'float',minf:'float',maxf:'float',roundf:'float',signf:'float',str:'String',range:'Array',is_finite:'bool'})[node.callee.name]??'Variant'):'Variant';
    for(const [key,value] of Object.entries(node)){if(['source','proof'].includes(key))continue;if(Array.isArray(value))value.forEach(x=>annotate(x,env));else if(value&&typeof value==='object')annotate(value,env);}
    if(node.kind==='binary'&&['+','-','*','/','%','**'].includes(node.op)){
      const a=node.left.type,b=node.right.type;
      if(a==='bool'||b==='bool')fail('Boolean arithmetic requires an explicit canonical numeric conversion',node.source);
      node.type=a==='String'||b==='String'?'String':a==='int'&&b==='int'?'int':a==='float'||b==='float'?'float':'Variant';
    }
    if(node.kind==='unary'&&node.op!=='not')node.type=node.value.type??'Variant';
    if(node.kind==='declare'){
      node.storageType=node.type==='Variant'&&(node.inferred||node.constant)?node.value?.type??'Variant':node.type;
      setOwn(env,node.name,node.storageType);
    }
    if(node.kind==='assign'){
      node.storageType=node.target.kind==='name'?env[node.target.name]??'Variant':'Variant';
      const a=node.target.type,b=node.value.type;
      node.operationType=a==='int'&&b==='int'?'int':a==='float'||b==='float'?'float':'Variant';
      if(node.op!=='='&&(a==='bool'||b==='bool'))fail('Boolean compound arithmetic requires an explicit canonical numeric conversion',node.source);
    }
    return node.type??'Variant';};
  const constantTypes={true:'bool',false:'bool',...Object.fromEntries(Object.keys(VARIANT_TYPES).map(name=>[name,'int']))};parsed.constants.forEach(n=>annotate(n,constantTypes));
  for(const fn of Object.values(functions)){const env={...constantTypes,...Object.fromEntries(fn.params.map(p=>[p.name,p.type]))};fn.body.forEach(n=>annotate(n,env));}
  const ir={schema:'canonical-gd-model-ir-v1',compilerVersion:COMPILER_VERSION,canonicalSourceSha256:hash(source),
    entrypoints:[...entrypoints],functions,constants:parsed.constants,boundaries:Object.fromEntries([...usedBoundaries].map(n=>[n,boundaries[n]])),inputSchema,
    coverage:{functions:Object.keys(functions).sort(),boundaries:[...usedBoundaries].sort(),nodes:locations,
      loops:Object.values(functions).flatMap(fn=>{const out=[];walkIR(fn,n=>{if(n.kind==='for'||n.kind==='while')out.push({id:n.id,source:n.source,proof:n.proof});});return out;})}};
  ir.irSha256=irFingerprint(ir);return ir;
}

// Numeric provenance is a tag, NEVER a Number.isInteger(value) guess. Source
// literals, casts, typed slots and container mutations carry this immutable tag.
// External JS numbers are unknown unless the caller explicitly supplies a tag
// or numericInputs:'float' for JSON-number data. Unknown int-vs-float division
// fails closed; integer-looking floating inputs remain floats.
class ModelNumber {
  constructor(value,numericType){this.value=value;this.numericType=numericType;Object.freeze(this);}
  valueOf(){return this.value;}
  toString(){return String(this.value);}
}
export const isModelNumber=value=>value instanceof ModelNumber;
export const rawNumber=value=>isModelNumber(value)?value.value:value;
export const numericKind=value=>isModelNumber(value)?value.numericType:'unknown';
export function modelNumber(value,numericType){
  if(typeof value!=='number'||!['int','float','unknown'].includes(numericType))throw new TypeError('modelNumber requires a numeric value and explicit int/float/unknown tag');
  if(numericType==='int'&&!Number.isSafeInteger(value))throw new RangeError('typed integer exceeds exact backend integer domain');
  return new ModelNumber(value,numericType);
}
export function gdType(value){return isModelNumber(value)?'number':value===null?'null':Array.isArray(value)?'array':typeof value==='object'?'dictionary':typeof value;}
const dictionaryValue=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&!isModelNumber(value)&&[Object.prototype,null].includes(Object.getPrototypeOf(value));
export function variantType(value){
  if(gdType(value)==='number'){
    const kind=numericKind(value);if(kind==='unknown')throw new TypeError('typeof numeric Variant requires exact int/float provenance');
    return kind==='int'?VARIANT_TYPES.TYPE_INT:VARIANT_TYPES.TYPE_FLOAT;
  }
  const result=({null:0,boolean:1,string:4,dictionary:27,array:28})[gdType(value)];
  if(result===undefined)throw new TypeError('typeof value is outside the represented Variant subset');return result;
}
export function modelArithmetic(op,a,b){
  if(op==='%'&&typeof a==='string')return binaryValue(op,a,b);
  if(op==='+'&&typeof a==='string'&&typeof b==='string')return a+b;
  if(gdType(a)!=='number'||gdType(b)!=='number')throw new TypeError('Boolean/non-numeric arithmetic requires an explicit canonical numeric conversion');
  const ka=numericKind(a),kb=numericKind(b),kind=ka==='float'||kb==='float'?'float':ka==='int'&&kb==='int'?'int':'unknown';
  if(op==='/'&&kind==='unknown')throw new TypeError('unproved Variant numeric division: bind exact int/float provenance or cast explicitly');
  if(op==='%'&&kind!=='int')throw new TypeError('numeric remainder requires proven integer operands');
  if(op==='**'&&kind==='int'&&rawNumber(b)<0)throw new TypeError('negative integer power is outside the proven numeric subset');
  const value=binaryValue(op,rawNumber(a),rawNumber(b));return modelNumber(kind==='int'?coerceTyped(value,'int'):value,kind);
}
// Adding 0.5 first changes already-integral odd values at 2^52. Compare the
// fractional remainder instead; preserve integers and signed zero exactly.
export function roundAway(value){if(!Number.isFinite(value)||Number.isInteger(value))return value;const a=Math.abs(value),whole=Math.floor(a);return Math.sign(value)*(whole+(a-whole>=0.5?1:0));}
export function coerceTyped(value,target){
  if(target==='Variant'||target==='void'||!target)return value;
  value=rawNumber(value);
  if(target==='int'||target==='float'){
    if(typeof value!=='number')throw new TypeError(`typed ${target} assignment needs a number`);
    const result=target==='int'?Math.trunc(value):value;
    if(target==='int'&&!Number.isSafeInteger(result))throw new RangeError('typed integer exceeds exact backend integer domain');
    return result;
  }
  const expected=({bool:'boolean',String:'string',Array:'array',Dictionary:'dictionary'})[target];
  if(gdType(value)!==expected)throw new TypeError(`typed ${target} assignment has incompatible value`);
  return value;
}
export function validFloatString(value){return typeof value==='string'&&/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value.trim())&&Number.isFinite(Number(value));}
const same=(a,b)=>{a=rawNumber(a);b=rawNumber(b);if(typeof a!==typeof b)return false;if(Array.isArray(a)&&Array.isArray(b))return a.length===b.length&&a.every((x,i)=>same(x,b[i]));if(a&&b&&typeof a==='object')return Object.keys(a).length===Object.keys(b).length&&Object.keys(a).every(k=>Object.hasOwn(b,k)&&same(a[k],b[k]));return a===b;};
// Array.has uses Variant-type-sensitive search, unlike ordinary int/float ==.
// Container membership is deliberately outside this qualified scalar subset.
function arrayMemberSame(a,b){
  for(const value of [a,b]){
    if(['array','dictionary'].includes(gdType(value)))throw new TypeError('Array.has membership supports scalar values only');
  }
  // A category mismatch is false without asking whether an unknown number was
  // int or float. Subtype provenance is needed only for an actual numeric pair.
  if(gdType(a)!==gdType(b))return false;
  if(gdType(a)==='number'&&[a,b].some(v=>numericKind(v)==='unknown'))throw new TypeError('Array.has membership requires exact numeric provenance');
  return variantType(a)===variantType(b)&&same(a,b);
}
const dictionaryKey=key=>{if(typeof key!=='string')throw new TypeError('dictionary key must be String; heterogeneous keys are outside the admitted subset');return key;};
// Bounded source str contract (Godot 4.6 Variant::stringify / num_real).
// Do not erase ModelNumber provenance or use host String for arbitrary Variant.
// Integral floats are deliberately restricted to a simple decimal domain; the
// general bounded-decimal/scientific formatter and signed-zero spelling are
// unqualified. This bound is formatting noncoverage, not a model/input limit.
function sourceString(value){
  if(value===null)return '<null>';
  if(typeof value==='string')return value;
  if(typeof value==='boolean')return value?'true':'false';
  if(gdType(value)==='number'){
    const kind=numericKind(value),number=rawNumber(value);
    if(kind==='unknown')throw new TypeError('str numeric value requires exact int/float provenance');
    if(kind==='int'&&Number.isSafeInteger(number))return String(number);
    if(kind==='float'&&Number.isSafeInteger(number)&&Math.abs(number)<=1000000&&!Object.is(number,-0))return String(number)+'.0';
    throw new TypeError('str numeric formatting domain is unqualified (finite safe int or simple integral float only)');
  }
  throw new TypeError('str container/Variant formatting domain is unqualified');
}
export function builtinValue(name,a,limit=100000){
  const numeric=x=>{if(typeof x==='boolean')return Number(x);if(typeof x==='number')return x;if(typeof x==='string'&&x.trim()!==''&&!Number.isNaN(Number(x)))return Number(x);throw new TypeError('invalid numeric conversion');};
  switch(name){
    case 'float':return numeric(a[0]);case 'int':return coerceTyped(numeric(a[0]),'int');case 'str':return sourceString(a[0]);case 'typeof':return variantType(a[0]);case 'is_finite':return typeof a[0]==='number'&&Number.isFinite(a[0]);
    case 'pow':return Math.pow(...a);case 'abs':return Math.abs(a[0]);case 'min':case 'minf':return Math.min(...a);case 'max':case 'maxf':return Math.max(...a);case 'clamp':return Math.min(a[2],Math.max(a[1],a[0]));
    case 'exp':return Math.exp(a[0]);case 'log':return Math.log(a[0]);case 'tanh':return Math.tanh(a[0]);case 'lerpf':return a[0]+(a[1]-a[0])*a[2];case 'round':case 'roundf':return roundAway(a[0]);case 'floor':return Math.floor(a[0]);case 'signf':return Math.sign(a[0]);
    case 'range':{const [start,end,step]=a.length===1?[0,a[0],1]:[a[0],a[1],a[2]??1];if(![start,end,step].every(Number.isSafeInteger)||!step)throw new RangeError('range needs finite integer bounds and a nonzero step');const count=Math.max(0,Math.ceil((end-start)/step));if(count>limit)throw new RangeError('range exceeds finite specialization limit');return Array.from({length:count},(_,i)=>start+i*step);}
    default:throw new Error(`unsupported builtin ${name}`);
  }
}
export function binaryValue(op,a,b){
  // Dispatch before unboxing: Variant-sensitive membership needs int/float tags.
  if(op==='in'||op==='not in'){
    let found;
    if(Array.isArray(b))found=b.some(x=>arrayMemberSame(x,a));
    else if(typeof b==='string'){if(typeof a!=='string')throw new TypeError('String membership requires a String needle');found=b.includes(a);}
    else if(dictionaryValue(b))found=Object.hasOwn(b,dictionaryKey(a));
    else throw new TypeError('membership requires an Array, Dictionary or String receiver');
    return op==='not in'?!found:found;
  }
  a=rawNumber(a);b=rawNumber(b);
  switch(op){case '+':if(typeof a==='string'&&typeof b==='string'||typeof a==='number'&&typeof b==='number')return a+b;throw new TypeError('mixed String/non-numeric arithmetic requires explicit conversion');case '-':return a-b;case '*':return a*b;case '/':return a/b;case '**':return a**b;
    case '%':{if(typeof a!=='string')return a%b;let i=0;const args=Array.isArray(b)?b:[b];return a.replace(/%(?:\.(\d+))?([sdf%])/g,(whole,digits,type)=>type==='%'?'%':type==='s'?String(args[i++]):type==='d'?String(Math.trunc(args[i++])):Number(args[i++]).toFixed(Number(digits??6)));}
    case '==':return same(a,b);case '!=':return !same(a,b);case '<':return a<b;case '>':return a>b;case '<=':return a<=b;case '>=':return a>=b;
    case 'is':return gdType(a)===b;default:throw new Error(`unsupported operator ${op}`);}
}

/** Pure reference interpreter of the very same IR. Not a Godot qualification. */
function evaluateModelInternal(ir,entrypoint,args=[],options={},constantBridge=false){
  if(ir.irSha256!==irFingerprint(ir))fail('IR fingerprint mismatch; recompile canonical source rather than editing IR');
  if(options.numericInputs!==undefined&&options.numericInputs!=='float')fail('numericInputs must be explicit float (JSON-number domain); otherwise use modelNumber tags');
  const globals={...PREDEFINED,...Object.fromEntries(Object.entries(VARIANT_TYPES).map(([name,value])=>[name,modelNumber(value,'int')])),INF:modelNumber(Infinity,'float'),NAN:modelNumber(NaN,'float')};let fuel=options.maxOperations??1000000;
  const structureVersions=new WeakMap(),resized=obj=>structureVersions.set(obj,(structureVersions.get(obj)??0)+1);
  const charge=n=>{if(--fuel<0)fail('pure interpreter operation budget exhausted',n?.source);};
  const copy=(value,convertNumbers=false,memo=new Map())=>{if(isModelNumber(value))return value;if(typeof value==='number')return convertNumbers?modelNumber(value,options.numericInputs??'unknown'):value;if(!value||typeof value!=='object')return value;if(!Array.isArray(value)&&!dictionaryValue(value))fail('copy/input requires an Array or plain String-key Dictionary');if(memo.has(value))return memo.get(value);const isArray=Array.isArray(value),info=!convertNumbers||Object.isFrozen(value)?dictionaryOrders.get(value):undefined,keys=isArray||!info?Object.keys(value):dictionaryKeys(value),result=isArray?[]:dictionary([],info?.unknown??keys.some(indexKey));memo.set(value,result);for(const k of keys)isArray?setOwn(result,k,copy(value[k],convertNumbers,memo)):dictionarySet(result,k,copy(value[k],convertNumbers,memo));return result;};
  const unbox=(value,memo=new Map())=>{if(isModelNumber(value))return value.value;if(!value||typeof value!=='object')return value;if(memo.has(value))return memo.get(value);const isArray=Array.isArray(value),result=isArray?[]:dictionary([],dictionaryOrders.get(value)?.unknown??Object.keys(value).some(indexKey));memo.set(value,result);for(const k of isArray?Object.keys(value):dictionaryKeys(value))isArray?setOwn(result,k,unbox(value[k],memo)):dictionarySet(result,k,unbox(value[k],memo));return result;};
  const truth=value=>isModelNumber(value)?value.value!==0:Array.isArray(value)?value.length>0:dictionaryValue(value)?dictionaryKeys(value).length>0:Boolean(value);
  const typed=(value,target)=>{if(['int','float'].includes(target))return modelNumber(coerceTyped(value,target),target);return coerceTyped(value,target);};
  const builtin=(name,values)=>{
    if(name==='str')return sourceString(values[0]);
    if(name==='typeof')return modelNumber(variantType(values[0]),'int');
    if(name==='is_finite')return gdType(values[0])==='number'&&Number.isFinite(rawNumber(values[0]));
    if(['pow','abs','min','max','minf','maxf','clamp','exp','log','tanh','lerpf','round','roundf','signf','floor'].includes(name)&&values.some(v=>gdType(v)!=='number'))fail('Boolean/non-numeric math requires explicit numeric conversion');
    const raw=values.map(v=>unbox(v)),value=builtinValue(name,raw,options.maxArrayLength??10000);
    if(name==='range')return value.map(x=>modelNumber(x,'int'));
    if(typeof value!=='number')return value;
    const kinds=values.map(numericKind),kind=name==='int'?'int':name==='float'||['pow','exp','log','tanh','lerpf','minf','maxf','roundf','signf'].includes(name)?'float':kinds.every(k=>k==='int')?'int':kinds.every(k=>k==='float')?'float':'unknown';
    return modelNumber(value,kind);
  };
  // Source property access is not JS boxing. Admit the receiver BEFORE any
  // own-property lookup or write; private ModelNumber fields are never source
  // Dictionary keys. Method calls retain their separate closed dispatch below.
  const arrayIndex=(obj,index,n)=>{
    if(gdType(index)!=='number'||!Number.isSafeInteger(rawNumber(index)))fail('array index requires a finite safe integral numeric value',n.source);
    let key=rawNumber(index);if(key<0)key+=obj.length;
    if(key<0||key>=obj.length)fail('array index out of bounds',n.source);return key;
  };
  const accessReceiver=(obj,member,n)=>{
    if(dictionaryValue(obj))return false;
    if(!member&&Array.isArray(obj))return true;
    fail(`${member?'member':'index'} access receiver must be ${member?'a plain Dictionary':'an Array or plain Dictionary'}`,n.source);
  };
  const accessKey=(obj,index,member,n)=>accessReceiver(obj,member,n)?arrayIndex(obj,index,n):dictionaryKey(index);
  const expr=(n,env)=>{charge(n);switch(n.kind){
    case 'literal':return typeof n.value==='number'?modelNumber(n.value,n.type):n.value;case 'name':if(Object.hasOwn(env,n.name))return env[n.name];if(Object.hasOwn(globals,n.name))return globals[n.name];fail(`unbound variable ${n.name}`,n.source);break;
    case 'array':return n.items.map(x=>expr(x,env));case 'dictionary':return dictionary(n.entries.map(x=>[dictionaryKey(expr(x.key,env)),expr(x.value,env)]));
    case 'member':{const obj=expr(n.object,env),key=accessKey(obj,n.name,true,n);if(!Object.hasOwn(obj,key))fail(`missing member ${key}`,n.source);return obj[key];}
    case 'index':{const obj=expr(n.object,env),index=expr(n.index,env),key=accessKey(obj,index,false,n);if(!Object.hasOwn(obj,key))fail(`missing index ${key}`,n.source);return obj[key];}
    case 'unary':{const v=expr(n.value,env);if(n.op==='not')return !truth(v);if(gdType(v)!=='number')fail('Boolean/non-numeric unary arithmetic requires explicit conversion',n.source);return modelNumber(n.op==='-'?-rawNumber(v):+rawNumber(v),numericKind(v));}
    case 'binary':{const a=expr(n.left,env);if(n.op==='and')return truth(a)&&truth(expr(n.right,env));if(n.op==='or')return truth(a)||truth(expr(n.right,env));const b=expr(n.right,env);return ['+','-','*','/','%','**'].includes(n.op)?modelArithmetic(n.op,a,b):binaryValue(n.op,a,b);}
    case 'conditional':return expr(truth(expr(n.condition,env))?n.yes:n.no,env);
    case 'call':{const c=n.callee,receiver=c.kind==='member'?expr(c.object,env):null,a=n.args.map(x=>expr(x,env));
      if(c.kind==='name')return BUILTINS.has(c.name)?builtin(c.name,a):call(c.name,a);
      const obj=receiver,name=c.name;
      const receiverKind=Array.isArray(obj)?'array':dictionaryValue(obj)?'dictionary':typeof obj==='string'?'string':'other';
      if(!METHOD_RECEIVERS[name]?.includes(receiverKind))fail(`method ${name} has invalid receiver kind ${receiverKind}`,n.source);
      if(name==='merge'&&!dictionaryValue(a[0]))fail('merge requires a Dictionary source',n.source);
      if(name==='append_array'&&!Array.isArray(a[0]))fail('append_array requires an Array source',n.source);
      switch(name){case 'get':{if(Array.isArray(obj)){if(a.length!==1)fail('Array.get requires one index argument',n.source);const key=arrayIndex(obj,a[0],n);return obj[key];}const key=dictionaryKey(a[0]);return Object.hasOwn(obj,key)?obj[key]:a[1]??null;}case 'has':return Array.isArray(obj)?obj.some(value=>arrayMemberSame(value,a[0])):Object.hasOwn(obj,dictionaryKey(a[0]));case 'size':return modelNumber(Array.isArray(obj)||typeof obj==='string'?obj.length:Object.keys(obj).length,'int');case 'is_empty':return (Array.isArray(obj)?obj.length:Object.keys(obj).length)===0;
        case 'duplicate':return truth(a[0])?copy(obj):Array.isArray(obj)?obj.slice():dictionary(dictionaryKeys(obj).map(k=>[k,obj[k]]),dictionaryOrders.get(obj)?.unknown??false);case 'slice':return obj.slice(...a.map(rawNumber));case 'append':resized(obj);obj.push(a[0]);return null;case 'append_array':if(a[0].length)resized(obj);obj.push(...a[0]);return null;case 'fill':obj.fill(a[0]);return null;
        case 'resize':{const length=rawNumber(a[0]);if(!Number.isSafeInteger(length)||length<0||length>(options.maxArrayLength??10000))fail('invalid/beyond-budget array resize',n.source);if(length!==obj.length)resized(obj);while(obj.length<length)obj.push(null);obj.length=length;return null;}
        case 'pop_back':if(!obj.length)fail('pop from empty array',n.source);resized(obj);return obj.pop();case 'pop_front':if(!obj.length)fail('pop from empty array',n.source);resized(obj);return obj.shift();case 'sort':obj.sort((a,b)=>a<b?-1:a>b?1:0);return null;
        case 'merge':for(const k of dictionaryKeys(a[0],true))if(truth(a[1])||!Object.hasOwn(obj,k))dictionarySet(obj,k,a[0][k]);return null;case 'values':return dictionaryKeys(obj,true).map(k=>obj[k]);case 'keys':return dictionaryKeys(obj,true);case 'is_valid_float':return validFloatString(obj);default:fail(`unsupported method ${name}`,n.source);}
    }default:fail(`unsupported expression ${n.kind}`,n.source);}};
  // Native4.7.2 assignment order: receiver, RHS, index, compound read, write.
  // Capture only the receiver now; resolve the index/location AFTER the RHS.
  const location=(target,env)=>{
    if(target.kind==='name')return ()=>({read:()=>env[target.name],write:value=>setOwn(env,target.name,value)});
    const obj=expr(target.object,env),member=target.kind==='member';
    accessReceiver(obj,member,target); // unsupported receivers never expose JS fields
    return ()=>{
      const index=member?target.name:expr(target.index,env),key=accessKey(obj,index,member,target);
      return {read:()=>{if(!Object.hasOwn(obj,key))fail('missing compound assignment target',target.source);return obj[key];},write:value=>{
        // Bounds and negative normalization use the live Array after RHS AND
        // index effects. Recheck before defineProperty; never append a ghost slot.
        return Array.isArray(obj)?setOwn(obj,arrayIndex(obj,index,target),value):dictionarySet(obj,key,value);
      }};
    };
  };
  const run=(body,env)=>{for(const n of body){charge(n);switch(n.kind){case 'declare':setOwn(env,n.name,typed(n.value?expr(n.value,env):null,n.storageType));break;case 'assign':{const resolve=location(n.target,env),rhs=expr(n.value,env),target=resolve(),value=n.op==='='?rhs:modelArithmetic(n.op[0],target.read(),rhs);target.write(typed(value,n.storageType));break;}
      case 'expression':expr(n.value,env);break;case 'return':return {value:expr(n.value,env)};case 'if':{const r=run(truth(expr(n.condition,env))?n.yes:n.no,env);if(r)return r;break;}
      case 'for':{const values=expr(n.iterable,env),isArray=Array.isArray(values),keys=isArray?Object.keys(values):dictionaryKeys(values,true),length=values.length,version=structureVersions.get(values)??0,count=isArray?length:keys.length;
        for(let i=0;i<count;i++){setOwn(env,n.name,isArray?values[i]:keys[i]);const r=run(n.body,env);
          if(isArray&&(values.length!==length||(structureVersions.get(values)??0)!==version))fail('for iterable is resized/mutated: no finite iteration proof',n.source);
          if(!isArray&&(Object.keys(values).length!==keys.length||keys.some(k=>!Object.hasOwn(values,k))))fail('for dictionary iterable key set is mutated: no finite iteration proof',n.source);
          if(r)return r;}break;}
      case 'while':while(truth(expr(n.condition,env))){const r=run(n.body,env);if(r)return r;}break;case 'pass':break;default:fail(`unsupported statement ${n.kind}`,n.source);}}return null;};
  const call=(name,values)=>{const boundary=Object.hasOwn(ir.boundaries,name)?ir.boundaries[name]:undefined;if(boundary){const supplied=options.inputs?.[boundary.input];if(supplied===undefined)fail(`missing input-only boundary ${boundary.input}`);const value=copy(supplied,true),valid=call(boundary.validator,[value]);return valid.ok?{ok:true,value}:valid;}
    const fn=ir.functions[name];if(!fn)fail(`unresolved function ${name}`);if(values.length>fn.params.length)fail(`too many arguments to ${name}`,fn.source);const env={};fn.params.forEach((p,i)=>{if(i<values.length)setOwn(env,p.name,typed(values[i],p.type));else if(p.value)setOwn(env,p.name,typed(expr(p.value,env),p.type));else fail(`missing argument ${name}.${p.name}`,p.source);});return typed(run(fn.body,env)?.value??null,fn.returns);};
  for(const n of ir.constants)setOwn(globals,n.name,typed(expr(n.value,globals),n.storageType));
  const internal=call(entrypoint,copy(args,true)),result=options.preserveNumericTypes?internal:unbox(internal);
  const finish=(value,seen=new Set())=>{
    if(!value||typeof value!=='object'||isModelNumber(value)||seen.has(value))return;seen.add(value);
    if(!constantBridge)dictionaryOrders.delete(value);
    for(const key of Object.keys(value))finish(value[key],seen);
    if(constantBridge)Object.freeze(value);
  };
  finish(result);return result;
}

export function evaluateModel(ir,entrypoint,args=[],options={}){return evaluateModelInternal(ir,entrypoint,args,options,false);}

export function modelConstants(ir,options={}){const wrapper={...ir,functions:{...ir.functions,__constants:{name:'__constants',params:[],body:[{kind:'return',value:{kind:'dictionary',entries:ir.constants.map(n=>({key:{kind:'literal',value:n.name},value:{kind:'name',name:n.name}}))}}]}},boundaries:{}};wrapper.irSha256=irFingerprint(wrapper);return evaluateModelInternal(wrapper,'__constants',[],options,true);}
