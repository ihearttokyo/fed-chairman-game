/** Pure, fail-closed metadata composition for model-excel output graphs.
 *
 * No workbook/engine, filesystem, model equations or import-time I/O. Values,
 * errors, source presence and availability formulas are NEVER rewritten. Only
 * fresh Boolean admission formulas and typed input-view metadata are produced.
 *
 * composeOutputs({formulas, descriptors, cellTypes}, options) returns an existing
 * emitter input tree (value), readyCell, fresh formulas, constraints and proofs.
 * The caller MUST gate the successor with readyCell. The optional `adopted` view
 * discharges optional wrappers ONLY under that exact readyCell (a conjunction
 * containing every source presence/availability). It is not an unconditional
 * replacement for value. This lets the existing emitter specialize a complete
 * container without inventing conditional lengths for already admitted shapes.
 * adoption is a SOURCE-derived
 * success/availability predicate, not an observed result or numeric assertion.
 * Descriptors are {path,cell,type,numericType,presenceCell}; describeOutputs makes
 * them from a bound emitted program without guessing types from cell values.
 * cellTypes maps external cells to existing emitter {type,numericType?} bindings.
 * Every upstream reference in formulas/predicates must already be bound to a
 * declared formula or typed input BEFORE helper allocation. An absent source
 * is not an implicit blank. Reference spelling is case-insensitive/canonical;
 * original formula text is never changed. Strings do not create references.
 *
 * Proofs use only alias, Boolean literal, lazy IF and NOT structure. Every other
 * formula (including arithmetic/comparisons, IFERROR, eager AND/OR and text) is
 * an independent atom. Proofs exclude NORMAL Boolean paths only: they are not
 * certificates that predicates cannot error. No underlying formula/guard is
 * simplified from a proof. Every selected presence (INCLUDING omitted paths)
 * gets a fresh IFERROR(ISLOGICAL(presence),FALSE) admission guard. Thus 'no normal
 * true path' cannot erase an errored presence into a healthy successor. All
 * omission certificates require this additional source-derived availability
 * predicate; the caller must retain it in readyCell.
 * Bounded
 * search, cycles and unknown work cannot authorize removing an alternative.
 *
 * The current input protocol cannot represent conditional numeric tags or live
 * scalar/container unions; those decline explicitly. Empty containers are NOT
 * encoded by emitted leaf metadata, so completeness of a whole source object
 * cannot be certified here. This is a LEAF PROJECTION, not a complete-container
 * schema oracle. The caller owns source-derived whole-object shape coverage.
 * Complete finite projected dictionaries/arrays have a ready guard;
 * individual source presence is still retained in every dictionary optional.
 * A source-absent or unavailable field makes this complete-shape view unavailable,
 * NOT a fabricated zero, empty dictionary or shorter array. This is a domain
 * restriction, not evidence that all valid source states have this shape.
 *
 * Hashes attribute ordinary closed data, not authenticated producer/custody
 * proof. Objects must be plain data (no accessors); hostile JS Proxies are not
 * an admitted serialization or a security boundary of this metadata API.
 */
import { createHash } from 'node:crypto';

export const COMPOSITION_VERSION='gd-compose-2';
export class CompositionError extends Error {
  constructor(code,message,details={}){super(`Composition refusal [${code}]: ${message}`);this.name='CompositionError';this.code=code;this.details=details;}
}
const refuse=(code,message,details)=>{throw new CompositionError(code,message,details);};
const own=(o,k)=>Object.hasOwn(o,k);
const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const forbidden=new Set(['__proto__','prototype','constructor']);
function record(value,label){
  if(value===null||typeof value!=='object'||![Object.prototype,null].includes(Object.getPrototypeOf(value)))refuse('METADATA',label+' must be plain data');
  for(const key of Reflect.ownKeys(value)){
    const descriptor=Object.getOwnPropertyDescriptor(value,key);
    if(typeof key!=='string'||forbidden.has(key)||!own(descriptor,'value')||!descriptor.enumerable)refuse('METADATA',label+' has unsafe/accessor/hidden metadata');
  }
  return value;
}
function dataArray(value,label){
  if(!Array.isArray(value)||Object.getPrototypeOf(value)!==Array.prototype)refuse('METADATA',label+' must be a dense ordinary array');
  const keys=Reflect.ownKeys(value);
  if(keys.length!==value.length+1||keys.some(k=>k!=='length'&&(typeof k!=='string'||!/^(0|[1-9][0-9]*)$/.test(k)||!own(Object.getOwnPropertyDescriptor(value,k),'value'))))refuse('METADATA',label+' has holes/accessors/extra keys');
  return value;
}
const sheets=new Map(['Policy Lab','Policy','Assumptions','Economy','Shocks'].map(s=>[s.toLowerCase(),s]));
function cell(value){
  if(typeof value!=='string')refuse('CELL','cell must be a string');
  const m=/^(?:'([^']+)'|([A-Za-z ]+))!\$?([A-Z]{1,3})\$?([1-9][0-9]*)$/i.exec(value),sheet=m&&sheets.get((m[1]??m[2]).toLowerCase()),column=m?.[3].toUpperCase();
  if(!m||!sheet||Number(m[4])>1048576||[...column].reduce((a,c)=>a*26+c.charCodeAt(0)-64,0)>16384)refuse('CELL','not an admitted local A1 cell: '+value);
  return `'${sheet}'!${column}${m[4]}`;
}
const isCell=s=>/^(?:'[^']+'|[A-Za-z ]+)!\$?[A-Z]{1,3}\$?[1-9][0-9]*$/i.test(s);
function expression(value){
  if(typeof value!=='string'||!value.length||value.length>8192)refuse('PREDICATE','predicate must be bounded formula text');
  const text=value.trim().replace(/^=/,'').trim();if(!text.length)refuse('PREDICATE','empty predicate');return text;
}
// Dependency admission for the existing ordinary scalar dialect, NOT an engine
// capability whitelist or a second economic evaluator. Unknown functions/names,
// ranges, indirect/external/relative references and unsupported tokens refuse.
// Arithmetic and error-sensitive calls remain opaque to the Boolean prover.
const scalarFunctions=new Set(['ABS','AND','EXACT','EXP','IF','IFERROR','INT','ISBLANK','ISLOGICAL','ISNUMBER','LN','MAX','MIN','NA','NOT','OR','POWER','ROUND','SIGN','TANH']);
function references(raw){
  const text=expression(raw),found=new Set();let i=0;
  while(i<text.length){
    const rest=text.slice(i),c=text[i];if(/\s/.test(c)){i++;continue;}
    if(c==='"'){
      let closed=false;i++;
      while(i<text.length){if(text[i++]!=='"')continue;if(text[i]==='"'){i++;continue;}closed=true;break;}
      if(!closed)refuse('DEPENDENCY_SYNTAX','unterminated quoted string');continue;
    }
    const ref=/^(?:'(?:[^']|'')+'|[A-Za-z][A-Za-z ]*)!\$?[A-Z]{1,3}\$?[1-9][0-9]*/i.exec(rest);
    if(ref){
      if(/[A-Za-z0-9_.$]/.test(text[i+ref[0].length]??''))refuse('DEPENDENCY_SYNTAX','ambiguous cell reference');
      found.add(cell(ref[0]));i+=ref[0].length;continue;
    }
    const number=/^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:E[+-]?[0-9]+)?/i.exec(rest);
    if(number){i+=number[0].length;continue;}
    const identifier=/^[A-Za-z_][A-Za-z_0-9.]*/.exec(rest);
    if(identifier){
      const name=identifier[0].toUpperCase(),next=text.slice(i+identifier[0].length).trimStart()[0];
      if(next==='('? !scalarFunctions.has(name):!['TRUE','FALSE'].includes(name))refuse('DEPENDENCY_SYNTAX','unproved function/name or unqualified reference '+identifier[0]);
      i+=identifier[0].length;continue;
    }
    if('()+-*/^&=<>%,'.includes(c)){i++;continue;}
    refuse('DEPENDENCY_SYNTAX','unsupported dependency syntax at '+rest.slice(0,32));
  }
  return found;
}
function requireBindings(expressions,graph){
  for(const [origin,text]of expressions)for(const ref of references(text))if(!own(graph.formulas,ref)&&!own(graph.cellTypes,ref))refuse('UNBOUND_DEPENDENCY','upstream cell is not a declared formula or typed input: '+ref,{cell:ref,origin});
}
// Exact outer syntax only. No numeric/text evaluation, regex reference scanning
// through strings, Excel parser approximation, or eager-error simplification.
function outer(text){
  text=expression(text);
  for(;;){
    if(text[0]!=='('||text.at(-1)!==')')return text;
    let depth=0,quote=null,whole=true;
    for(let i=0;i<text.length;i++){
      const c=text[i];if(quote){if(c===quote){if(text[i+1]===quote)i++;else quote=null;}continue;}
      if(c==='"'||c==="'"){quote=c;continue;}if(c==='(')depth++;else if(c===')')depth--;
      if(depth===0&&i!==text.length-1){whole=false;break;}if(depth<0)return text;
    }
    if(!whole||quote||depth!==0)return text;text=text.slice(1,-1).trim();
  }
}
function call(text,name,arity){
  text=outer(text);if(!text.startsWith(name+'(')||text.at(-1)!==')')return null;
  const args=[];let depth=0,start=name.length+1,quote=null;
  for(let i=start;i<text.length;i++){
    const c=text[i];if(quote){if(c===quote){if(text[i+1]===quote)i++;else quote=null;}continue;}
    if(c==='"'||c==="'"){quote=c;continue;}
    if(c==='(')depth++;else if(c===')'){
      if(depth===0){if(i!==text.length-1)return null;args.push(text.slice(start,i).trim());}else depth--;
    }else if(c===','&&depth===0){args.push(text.slice(start,i).trim());start=i+1;}
  }
  return !quote&&depth===0&&args.length===arity&&args.every(Boolean)?args:null;
}
class ProofLimit extends Error {}
function positiveInteger(value,fallback,name){
  const v=value??fallback;if(!Number.isSafeInteger(v)||v<1)refuse('LIMIT',name+' must be a positive safe integer');return v;
}
function admitGraph(graph){
  record(graph,'graph');const formulas=Object.create(null),cellTypes=Object.create(null),occupied=new Set();
  for(const [name,value]of Object.entries(record(graph.formulas??{},'formulas'))){
    const key=cell(name);if(occupied.has(key))refuse('CELL_ALIAS','multiple spellings of '+key);occupied.add(key);
    if(typeof value!=='string'||!value.startsWith('=')||value.length>8192)refuse('FORMULA','expected bounded scalar formula at '+key);formulas[key]=value;
  }
  for(const [name,value]of Object.entries(record(graph.cellTypes??{},'cellTypes'))){
    const key=cell(name);record(value,'cell type');if(own(cellTypes,key))refuse('CELL_ALIAS','multiple input spellings of '+key);
    if(!['boolean','string','number','variant'].includes(value.type)||value.type==='number'&&!['int','float'].includes(value.numericType))refuse('METADATA','explicit input category/numeric provenance required at '+key);
    cellTypes[key]={type:value.type,...(value.type==='number'?{numericType:value.numericType}:{})};
  }
  requireBindings(Object.entries(formulas),{formulas,cellTypes});
  return {formulas,cellTypes};
}

export class BooleanProof {
  constructor(graph,options={}){
    record(options,'proof options');const admitted=admitGraph(graph);this.formulas=admitted.formulas;this.cellTypes=admitted.cellTypes;
    Object.freeze(this.formulas);for(const v of Object.values(this.cellTypes))Object.freeze(v);Object.freeze(this.cellTypes);
    this.maxSteps=positiveInteger(options.maxSteps,100000,'maxSteps');this.maxBranches=positiveInteger(options.maxBranches,64,'maxBranches');
    this.maxDepth=positiveInteger(options.maxDepth,64,'maxDepth');this.maxAliasDepth=positiveInteger(options.maxAliasDepth,2048,'maxAliasDepth');
    this.cache=new Map();this.terms=new Map();this.results=new Map();this.statistics={queries:0,proved:0,unknown:0,steps:0,branches:0,parsedExpressions:0};
    this.graphSha256=hash(admitted);
  }
  // Resolve aliases and negation only. IF subtrees expand on demand; opaque
  // expressions never expose their arithmetic/error-sensitive children.
  _term(raw,budget){
    if(++budget.steps>this.maxSteps)throw new ProofLimit('proof work exhausted');
    if(this.terms.has(raw))return this.terms.get(raw);
    let text=outer(raw),negative=false;const seen=new Set();
    const done=t=>{this.terms.set(raw,t);return t;};
    for(let depth=0;;depth++){
      if(++budget.steps>this.maxSteps||depth>=this.maxAliasDepth)throw new ProofLimit('proof work exhausted');
      if(text==='TRUE'||text==='FALSE')return done({constant:(text==='TRUE')!==negative});
      const key=isCell(text)?cell(text):text;
      if(seen.has(key))throw new ProofLimit('cyclic predicate');seen.add(key);
      let parsed=this.cache.get(key);
      if(!parsed){
        let body=key;
        if(isCell(key)){
          if(own(this.formulas,key))body=outer(this.formulas[key]);
          else if(!own(this.cellTypes,key))throw new ProofLimit('unbound predicate '+key);
        }
        const args=call(body,'IF',3),not=call(body,'NOT',1);
        parsed=body==='TRUE'||body==='FALSE'?{kind:'alias',body}:not?{kind:'not',body:not[0]}:args?{kind:'if',args}:body!==key&&isCell(body)?{kind:'alias',body}:{kind:'atom'};
        this.cache.set(key,parsed);this.statistics.parsedExpressions++;
      }
      if(parsed.kind==='alias'||parsed.kind==='not'){if(parsed.kind==='not')negative=!negative;text=outer(parsed.body);continue;}
      return done({id:key,node:parsed,negative});
    }
  }
  unreachable(predicates){
    dataArray(predicates,'predicates');const inputs=predicates.map(p=>{
      if(typeof p==='string')return {expression:expression(p),value:true};record(p,'signed predicate');
      if(typeof p.value!=='boolean')refuse('PREDICATE','signed predicate needs Boolean value');return {expression:expression(p.expression),value:p.value};
    });
    const key=JSON.stringify(inputs);if(this.results.has(key))return this.results.get(key);
    const budget={steps:0,branches:0};let reason='possible in Boolean over-approximation',proved=false;
    const solve=(given,depth)=>{
      if(depth>this.maxDepth)throw new ProofLimit('branch depth exhausted');
      const assigned=new Map(),constraints=new Map();let changed=false;
      const truth=t=>own(t,'constant')?t.constant:assigned.has(t.id)?assigned.get(t.id)!==t.negative:undefined;
      const assume=(t,want)=>{
        if(own(t,'constant'))return t.constant===want;
        const actual=want!==t.negative;if(assigned.has(t.id))return assigned.get(t.id)===actual;
        assigned.set(t.id,actual);if(t.node.kind==='if')constraints.set(t.id,t.node);changed=true;return true;
      };
      for(const [t,want]of given)if(!assume(t,want))return true;
      let unresolved;
      do{
        changed=false;unresolved=null;
        for(const [id,node]of constraints){
          if(++budget.steps>this.maxSteps)throw new ProofLimit('proof work exhausted');
          const want=assigned.get(id),[c,y,n]=node.args.map(x=>this._term(x,budget)),cv=truth(c),yv=truth(y),nv=truth(n);
          if(cv!==undefined){if(!assume(cv?y:n,want))return true;}
          else if(yv!==undefined&&yv!==want){if(!assume(c,false)||!assume(n,want))return true;}
          else if(nv!==undefined&&nv!==want){if(!assume(c,true)||!assume(y,want))return true;}
          else if(yv!==want||nv!==want)unresolved??=c;
        }
      }while(changed);
      if(!unresolved)return false;
      if(++budget.branches>this.maxBranches)throw new ProofLimit('branch budget exhausted');
      const facts=[...assigned].map(([id,want])=>[{id,node:this.cache.get(id),negative:false},want]);
      return solve([...facts,[unresolved,true]],depth+1)&&solve([...facts,[unresolved,false]],depth+1);
    };
    try{proved=solve(inputs.map(p=>[this._term(p.expression,budget),p.value]),0);if(proved)reason='unsatisfiable Boolean over-approximation';}
    catch(error){if(!(error instanceof ProofLimit))throw error;reason=error.message;}
    this.statistics.queries++;this.statistics[proved?'proved':'unknown']++;this.statistics.steps+=budget.steps;this.statistics.branches+=budget.branches;
    const result={proved,reason,steps:budget.steps,branches:budget.branches,graphSha256:this.graphSha256,predicates:inputs};this.results.set(key,result);return result;
  }
  implies(premises,consequence){dataArray(premises,'premises');return this.unreachable([...premises,{expression:consequence,value:false}]);}
}

export function pathTokens(path){
  if(typeof path!=='string'||!path.length||path.length>4096)refuse('PATH','expected bounded source path');
  const tokens=[];let end=0;
  for(const m of path.matchAll(/(?:^|\.)([A-Za-z_][A-Za-z_0-9]*)|\[(0|[1-9][0-9]*)\]/g)){
    if(m.index!==end)refuse('PATH','ambiguous source path '+path);end+=m[0].length;
    const token=m[1]??Number(m[2]);if(forbidden.has(token)||typeof token==='number'&&!Number.isSafeInteger(token))refuse('PATH','unsafe source path '+path);tokens.push(token);
  }
  if(end!==path.length||!tokens.length||typeof tokens[0]!=='string')refuse('PATH','unrepresented source path '+path);return tokens;
}
function numericLeaves(d,path=[],seen=new Set(),count={n:0}){
  if(++count.n>4096||path.length>64)refuse('METADATA','numeric descriptor budget exceeded');
  if(d===null||d==='int'||d==='float')return [{type:d,path}];
  record(d,'numeric descriptor');if(seen.has(d))refuse('METADATA','cyclic numeric descriptor');
  if(Object.keys(d).sort().join(',')!=='condition,no,yes')refuse('METADATA','unknown numeric descriptor fields');
  const condition=expression(d.condition),next=new Set(seen);next.add(d);
  return [...numericLeaves(d.yes,[...path,{expression:condition,value:true}],next,count),...numericLeaves(d.no,[...path,{expression:condition,value:false}],next,count)];
}
// Leading source availability gates are exactly lazy IF(g,value,NA()). Unknown
// syntax is NOT a reason to invent availability; composition declines it.
function availability(formula){
  const guards=[];let text=outer(formula);
  for(;;){const args=call(text,'IF',3);if(!args||outer(args[2])!=='NA()')break;guards.push(args[0]);text=outer(args[1]);}
  if(!guards.length)refuse('AVAILABILITY','output lacks an explicit source availability/NA gate');return guards;
}

export function describeOutputs(program){
  record(program,'emitted program');record(program.outputs,'outputs');record(program.outputPresence,'outputPresence');record(program.outputNumericTypes??{},'outputNumericTypes');dataArray(program.sourceMap,'sourceMap');
  const maps=program.sourceMap.map(x=>record(x,'sourceMap entry'));
  return Object.keys(program.outputs).map(path=>{
    pathTokens(path);const entries=maps.filter(x=>x.output===path&&!x.inlined);
    if(entries.length!==1)refuse('OUTPUT_BINDING','output must have one explicit destination '+path);
    const m=entries[0];return {path,cell:cell(m.cell),type:m.type,numericType:program.outputNumericTypes?.[path]??null,presence:expression(program.outputPresence[path])};
  });
}

export function composeOutputs(graph,options={}){
  record(graph,'composition graph');record(options,'composition options');const begin=performance.now();
  const proof=new BooleanProof(graph,options.proof??{}),descriptors=dataArray(graph.descriptors,'descriptors');
  // Admit the ENTIRE descriptor tree before selection, equality or JSON/hash.
  // In particular, dead/unselected paths cannot conceal toJSON callbacks.
  for(const d of descriptors){
    record(d,'descriptor');if(Object.keys(d).some(k=>!['path','cell','type','numericType','presenceCell','presence'].includes(k)))refuse('METADATA','unknown descriptor fields');
    pathTokens(d.path);cell(d.cell);expression(d.presenceCell??d.presence);
    if(!['number','boolean','string','null','dictionary','array','variant'].includes(d.type))refuse('METADATA','unknown descriptor category');
    if(d.numericType!==null&&d.numericType!==undefined)numericLeaves(d.numericType);
    if(d.presence!==undefined)expression(d.presence);if(d.presenceCell!==undefined)cell(d.presenceCell);
  }
  const prefix=options.prefix??'',prefixParts=prefix?pathTokens(prefix):[],adoption=expression(options.adoption??'TRUE');
  // Check ALL descriptor/predicate dependencies before creating even the first
  // helper. Otherwise a fresh guard could bind a previously unavailable source.
  const upstream=[['adoption',adoption]];
  for(const d of descriptors){
    upstream.push([d.path+' value',d.cell],[d.path+' presence',d.presenceCell??d.presence]);
    if(d.presence!==undefined)upstream.push([d.path+' alternate presence',d.presence]);
    if(d.numericType!==null&&d.numericType!==undefined)for(const leaf of numericLeaves(d.numericType))for(const p of leaf.path)upstream.push([d.path+' numeric choice',p.expression]);
  }
  requireBindings(upstream,proof);
  const shape={children:new Map()},proofs=[],omitted=[],retained=[],constraints=[],presenceAdmission=[],formulas={},guardIntern=new Map(),occupied=new Set([...Object.keys(proof.formulas),...Object.keys(proof.cellTypes)]);
  let row=positiveInteger(options.helperStartRow,2000,'helperStartRow');const sheet=options.helperSheet??'Economy',column=options.helperColumn??'L';
  if(typeof sheet!=='string'||typeof column!=='string')refuse('CELL','helper sheet/column must be strings');cell(`'${sheet}'!${column}${row}`);
  const fresh=formula=>{if(guardIntern.has(formula))return guardIntern.get(formula);const address=cell(`'${sheet}'!${column}${row++}`);if(occupied.has(address))refuse('CELL_COLLISION','composition guard collides at '+address);occupied.add(address);if(formula.length>8192)refuse('FORMULA','composition guard too long');formulas[address]=formula;guardIntern.set(formula,address);return address;};
  const conjunction=expressions=>{
    let layer=[...new Set(expressions)];if(!layer.length)return 'TRUE';
    while(layer.length>1){const next=[];for(let i=0;i<layer.length;i+=2)next.push(i+1===layer.length?layer[i]:fresh(`=IF(${layer[i]},${layer[i+1]},FALSE)`));layer=next;}
    return layer[0];
  };
  const adoptionAdmission=fresh(`=IFERROR(ISLOGICAL(${adoption}),FALSE)`);
  constraints.push({path:prefix,kind:'source-adoption-type',predicate:adoption,requiredCell:adoptionAdmission});
  for(const d of descriptors){
    record(d,'descriptor');const tokens=pathTokens(d.path); // Validate even unselected paths.
    if(prefixParts.some((p,i)=>tokens[i]!==p)||tokens.length<=prefixParts.length)continue;
    const valueCell=cell(d.cell),present=expression(d.presenceCell??d.presence);
    if(!own(proof.formulas,valueCell))refuse('OUTPUT_BINDING','source output cell has no formula '+valueCell);
    const available=availability(proof.formulas[valueCell]),mask=[adoption,present,...available];
    const wellTyped=fresh(`=IFERROR(ISLOGICAL(${present}),FALSE)`);presenceAdmission.push(wellTyped);
    constraints.push({path:d.path,kind:'source-presence-type',predicate:present,requiredCell:wellTyped});
    // Unavailable is NOT absent. A live but unavailable leaf must disable the
    // complete view, not disappear and launder its source shape into success.
    const dead=proof.unreachable([adoption,present]);
    if(dead.proved){omitted.push({path:d.path,cell:valueCell,reason:'no normal true presence under adoption; errored presence still vetoes readyCell',requiredPresenceAdmission:wellTyped});proofs.push(dead);continue;}
    let type=d.type,numericType=null;
    if(d.numericType!==null&&d.numericType!==undefined){
      const reachable=[];
      for(const leaf of numericLeaves(d.numericType)){
        const result=proof.unreachable([...mask,...leaf.path]);if(result.proved)proofs.push(result);else reachable.push(leaf.type);
      }
      const distinct=[...new Set(reachable)];
      if(distinct.length!==1||!['int','float'].includes(distinct[0]))refuse('CONDITIONAL_TYPE','reachable numeric/category alternatives cannot bind '+d.path,{path:d.path,alternatives:distinct});
      if(!['number','dictionary'].includes(type))refuse('UNREPRESENTED_TYPE','numeric descriptor/category mismatch at '+d.path);
      type='number';numericType=distinct[0];
    }
    if(!['number','boolean','string'].includes(type)||type==='number'&&!numericType)refuse('UNREPRESENTED_TYPE','no exact scalar input type for '+d.path,{path:d.path,type});
    let node=shape;
    for(const token of tokens.slice(prefixParts.length)){
      if(node.leaf)refuse('PATH_OVERLAP','live scalar/container alternatives at '+d.path,{path:d.path,other:node.leaf.path});
      if(!node.children.has(token))node.children.set(token,{children:new Map()});node=node.children.get(token);
    }
    if(node.leaf)refuse('DUPLICATE_PATH','duplicate live output '+d.path);
    if(node.children.size)refuse('PATH_OVERLAP','live scalar/container alternatives at '+d.path,{path:d.path});
    node.leaf={...d,cell:valueCell,type,numericType,present,available};retained.push(d.path);
  }
  if(!retained.length)refuse('NO_OUTPUTS','no representable source output paths for '+prefix,{omitted});
  const build=(node,path)=>{
    if(node.leaf){
      const d=node.leaf,presentCell=isCell(d.present)?cell(d.present):fresh('='+d.present),available=conjunction(d.available.map(p=>fresh(`=IF(IFERROR(ISLOGICAL(${p}),FALSE),${p},FALSE)`)));
      constraints.push({path:d.path,kind:'source-availability',presenceCell:presentCell,predicates:d.available.slice()});
      const value={cell:d.cell,type:d.type,...(d.type==='number'?{numericType:d.numericType}:{})};
      return {value,adopted:value,present:{cell:presentCell,type:'boolean'},ready:conjunction([presentCell,available])};
    }
    const keys=[...node.children.keys()],array=keys.every(k=>typeof k==='number');
    if(!array&&keys.some(k=>typeof k!=='string'))refuse('MIXED_CONTAINER','mixed dictionary/array at '+path);
    if(array){keys.sort((a,b)=>a-b);if(keys.some((k,i)=>k!==i))refuse('SPARSE_ARRAY','finite complete array required at '+path);}
    const children=keys.map(k=>[k,build(node.children.get(k),path+(array?`[${k}]`:'.'+k))]),ready=conjunction(children.map(([,c])=>c.ready));
    const present=conjunction(children.map(([,c])=>c.present.cell));
    constraints.push({path,kind:array?'complete-source-array-only':'complete-source-dictionary-only',...(array?{length:keys.length}:{keys:keys.slice()}),readyCell:ready});
    // Containers are represented only while their complete source shape is
    // present. Optional leaf predicates remain original, not the ready guard.
    const value=array?children.map(([,c])=>c.value):Object.fromEntries(children.map(([k,c])=>[k,{$optional:true,present:c.present,value:c.value}]));
    const adopted=array?children.map(([,c])=>c.adopted):Object.fromEntries(children.map(([k,c])=>[k,c.adopted]));
    return {value,adopted,present:{cell:isCell(present)?cell(present):fresh('='+present),type:'boolean'},ready};
  };
  const built=build(shape,prefix),ready=conjunction([adoptionAdmission,adoption,...presenceAdmission,built.ready]),readyCell=isCell(ready)?cell(ready):fresh('='+ready);
  return {schema:'canonical-gd-composition-v1',version:COMPOSITION_VERSION,value:built.value,readyCell,
    adopted:{value:built.adopted,predicate:readyCell,proofKind:'complete-leaf-projection-conjunction',projectionOnly:true,adoptionAdmission,presenceAdmission,obligations:constraints.filter(c=>c.kind==='source-availability').map(c=>({path:c.path,presenceCell:c.presenceCell,predicates:c.predicates}))},
    formulas,constraints,proofs,omitted,retainedPaths:retained,
    provenance:{graphSha256:proof.graphSha256,descriptorsSha256:hash(descriptors),adoption,metadataOnly:true},
    statistics:{...proof.statistics,addedGuardCells:Object.keys(formulas).length,elapsedMilliseconds:performance.now()-begin},
    qualification:'Complete emitted leaf projection only; caller must gate successor with readyCell AND separately establish whole-object container coverage (empty containers are unencoded). Unknown/conditional/partial shapes decline or remain unavailable; no engine or full-horizon qualification.'};
}

/** Complete finite source-shape view, admitted by an explicit runtime guard.
 * Unlike composeOutputs' leaf projection, this consumes gd-output-structure-v1.
 * Empty containers and source key order are preserved. Conditional scalar
 * values remain the original emitted cells. Unknown order, mixed scalar tags
 * and changing container shapes refuse; a shortened live array makes this
 * complete-capacity view unavailable, never silently padded or truncated.
 * The caller MUST gate successor outputs with readyCell. No source predicates
 * or values are rewritten and no expected/native values enter this operation.
 */
export function composeWholeOutputs(graph,options={}){
  record(graph,'whole composition graph');record(options,'whole composition options');
  const structure=record(graph.structure,'source structure');
  if(structure.schema!=='gd-output-structure-v1'||Object.keys(structure).some(k=>!['schema','availability','root','qualification'].includes(k))||structure.qualification!==undefined&&typeof structure.qualification!=='string')refuse('STRUCTURE','unsupported source structure schema/fields');
  const proof=new BooleanProof(graph,options.proof??{}),descriptors=dataArray(graph.descriptors,'descriptors');
  const prefix=options.prefix??'',prefixParts=prefix?pathTokens(prefix):[],adoption=expression(options.adoption??'TRUE');
  const dependencies=[['adoption',adoption],['source availability',expression(structure.availability)]],byPath=new Map();
  for(const d of descriptors){
    record(d,'descriptor');if(Object.keys(d).some(k=>!['path','cell','type','numericType','presenceCell','presence'].includes(k)))refuse('METADATA','unknown whole descriptor fields');const parts=pathTokens(d.path),key=JSON.stringify(parts);cell(d.cell);
    if(byPath.has(key))refuse('DUPLICATE_PATH','duplicate source descriptor '+d.path);
    if(!['number','boolean','string','null','dictionary','array','variant'].includes(d.type))refuse('METADATA','unknown whole descriptor category');
    if(d.presence!==undefined)dependencies.push([d.path+' alternate presence',expression(d.presence)]);if(d.presenceCell!==undefined)cell(d.presenceCell);
    byPath.set(key,d);dependencies.push([d.path,d.cell],[d.path+' presence',expression(d.presenceCell??d.presence)]);
    if(d.numericType!==null&&d.numericType!==undefined)for(const leaf of numericLeaves(d.numericType))for(const p of leaf.path)dependencies.push([d.path+' numeric type',p.expression]);
  }
  let nodes=0;const seen=new Set(),structuralTypes=[];
  // Source return-arm chains are deep but finite (not nested containers).
  // Validate iteratively rather than raising a recursive stack/depth budget.
  const pending=[{node:structure.root,expected:[]}];
  while(pending.length){
    const {node,expected,exit}=pending.pop();if(exit){seen.delete(node);continue;}
    record(node,'structural node');if(++nodes>20000||seen.has(node))refuse('STRUCTURE','cyclic or oversized source structure');
    seen.add(node);pending.push({node,exit:true});
    if(typeof node.kind!=='string'||!['choice','dictionary','array','scalar','absent'].includes(node.kind))refuse('STRUCTURE','unknown source structural kind');
    const allowed={choice:['condition','yes','no'],dictionary:['order','entries'],array:['length','items'],scalar:['type','numericType'],absent:[]}[node.kind];
    if(!allowed||Object.keys(node).some(k=>!['kind','segments','presence',...allowed].includes(k)))refuse('STRUCTURE','unknown structural node fields');
    dataArray(node.segments,'segments');
    for(const p of node.segments)if(typeof p==='string'?forbidden.has(p):typeof p!=='number'||!Number.isSafeInteger(p)||p<0)refuse('PATH','unsafe source segment');
    if(node.segments.length>128||JSON.stringify(node.segments)!==JSON.stringify(expected))refuse('STRUCTURE','source child path mismatch or excessive container depth');
    dependencies.push(['structural presence',expression(node.presence)]);structuralTypes.push({predicate:node.presence,when:null});
    if(node.kind==='choice'){
      dependencies.push(['structural choice',expression(node.condition)]);structuralTypes.push({predicate:node.condition,when:node.presence});
      pending.push({node:node.no,expected:node.segments},{node:node.yes,expected:node.segments});
    }else if(node.kind==='dictionary'){
      if(!['source-insertion','unproved'].includes(node.order))refuse('STRUCTURE','missing source Dictionary order');
      dataArray(node.entries,'dictionary entries');const keys=new Set();
      for(const entry of node.entries){record(entry,'dictionary entry');if(Object.keys(entry).some(k=>!['key','node'].includes(k))||typeof entry.key!=='string'||forbidden.has(entry.key)||keys.has(entry.key))refuse('STRUCTURE','unsafe/duplicate Dictionary entry');keys.add(entry.key);pending.push({node:entry.node,expected:[...node.segments,entry.key]});}
    }else if(node.kind==='array'){
      dependencies.push(['source array length',expression(node.length)]);dataArray(node.items,'array items');
      node.items.forEach((item,index)=>pending.push({node:item,expected:[...node.segments,index]}));
    }else if(node.kind==='scalar'){
      if(!['number','boolean','string','null'].includes(node.type))refuse('UNREPRESENTED_TYPE','unsupported source scalar type');
      if(node.numericType!==null&&node.numericType!==undefined)for(const leaf of numericLeaves(node.numericType))for(const p of leaf.path)dependencies.push(['structural numeric type',p.expression]);
    }
  }
  requireBindings(dependencies,proof); // BEFORE allocation, even inactive alternatives.
  const occupied=new Set([...Object.keys(proof.formulas),...Object.keys(proof.cellTypes)]),formulas={},intern=new Map(),constraints=[];
  let row=positiveInteger(options.helperStartRow,2000,'helperStartRow');const sheet=options.helperSheet??'Economy',column=options.helperColumn??'O';if(typeof sheet!=='string'||typeof column!=='string')refuse('CELL','whole helper sheet/column must be strings');cell(`'${sheet}'!${column}${row}`);
  const fresh=formula=>{
    if(intern.has(formula))return intern.get(formula);const address=cell(`'${sheet}'!${column}${row++}`);
    if(occupied.has(address))refuse('CELL_COLLISION','whole composition helper collides at '+address);if(formula.length>8192)refuse('FORMULA','whole composition guard too long');
    occupied.add(address);formulas[address]=formula;intern.set(formula,address);return address;
  };
  const strict=p=>fresh(`=IF(IFERROR(ISLOGICAL(${p}),FALSE),${p},FALSE)`);
  const combine=(values,all=true)=>{
    let layer=[...new Set(values)];if(!layer.length)return all?'TRUE':'FALSE';
    while(layer.length>1){const next=[];for(let i=0;i<layer.length;i+=2)next.push(i+1===layer.length?layer[i]:fresh(all?`=IF(${layer[i]},${layer[i+1]},FALSE)`:`=IF(${layer[i]},TRUE,${layer[i+1]})`));layer=next;}return layer[0];
  };
  const under=(node,parent)=>({...node,presence:combine([strict(node.presence),parent])});
  const branch=(node,yes)=>yes?strict(node.condition):fresh(`=IF(IFERROR(ISLOGICAL(${node.condition}),FALSE),NOT(${node.condition}),FALSE)`);
  const alternatives=values=>{
    const out=[],stack=[...values].reverse();
    while(stack.length){const n=stack.pop();if(n.kind==='choice')stack.push(under(n.no,combine([strict(n.presence),branch(n,false)])),under(n.yes,combine([strict(n.presence),branch(n,true)])));else if(n.kind!=='absent')out.push(n);}return out;
  };
  const candidates=[],locations=[structure.root];
  while(locations.length){const node=locations.pop();
    if(JSON.stringify(node.segments)===JSON.stringify(prefixParts)){candidates.push(node);continue;}
    if(prefixParts.some((p,i)=>node.segments[i]!==p&&i<node.segments.length))continue;
    if(node.kind==='choice')locations.push(under(node.no,combine([strict(node.presence),branch(node,false)])),under(node.yes,combine([strict(node.presence),branch(node,true)])));
    if(node.kind==='dictionary')for(const e of node.entries)locations.push(under(e.node,strict(node.presence)));
    if(node.kind==='array')for(const item of node.items)locations.push(under(item,strict(node.presence)));
  }
  if(!candidates.length)refuse('NO_OUTPUTS','source structure has no requested prefix');
  // Follow output relays without erasing their source availability predicates.
  const sourceAvailability=address=>{
    const visited=new Set();let current=cell(address);
    for(;;){if(visited.has(current))refuse('AVAILABILITY','cyclic output relay');visited.add(current);
      const f=proof.formulas[current];if(typeof f!=='string')refuse('OUTPUT_BINDING','output lacks source formula '+current);
      const raw=outer(f);if(isCell(raw)){current=cell(raw);continue;}return availability(f);
    }
  };
  const build=values=>{
    const live=alternatives(values);if(!live.length)refuse('NO_OUTPUTS','all structural alternatives absent');
    const first=live[0],requirements=[combine(live.map(n=>strict(n.presence)),false)];
    if(live.some(n=>n.kind!==first.kind))refuse('CONDITIONAL_SHAPE','container/scalar alternatives need explicit shape specialization');
    if(first.kind==='scalar'){
      if(live.some(n=>n.type!==first.type))refuse('CONDITIONAL_TYPE','source scalar category alternatives differ');
      const key=JSON.stringify(first.segments),d=byPath.get(key)??(first.segments.length===0||typeof first.segments[0]==='number'?byPath.get(JSON.stringify(['result',...first.segments])):undefined);if(!d)refuse('OUTPUT_BINDING','scalar has no source cell '+key);
      const numeric=first.type==='number'?[...new Set(live.flatMap(n=>numericLeaves(n.numericType).map(x=>x.type)))]:[];
      if(first.type==='number'&&(numeric.length!==1||!['int','float'].includes(numeric[0])))refuse('CONDITIONAL_TYPE','source numeric subtype alternatives differ or are unproved');
      if(first.type==='number'){
        const declared=[...new Set(numericLeaves(d.numericType).map(x=>x.type))];
        if(!['number','dictionary'].includes(d.type)||declared.length!==1||declared[0]!==numeric[0])refuse('TYPE_MISMATCH','descriptor and source numeric tags contradict');
      }else if(d.type!==first.type||d.numericType!==null&&d.numericType!==undefined)refuse('TYPE_MISMATCH','descriptor and source scalar categories contradict');
      requirements.push(strict(expression(d.presenceCell??d.presence)),...sourceAvailability(d.cell).map(strict));
      if(first.type==='null')return {value:null,ready:combine(requirements)};
      return {value:{cell:cell(d.cell),type:first.type,...(numeric.length?{numericType:numeric[0]}:{})},ready:combine(requirements)};
    }
    if(first.kind==='dictionary'){
      if(live.some(n=>n.order!=='source-insertion'))refuse('ORDER','Dictionary source insertion order is unproved');
      const keys=first.entries.map(e=>e.key);
      if(live.some(n=>JSON.stringify(n.entries.map(e=>e.key))!==JSON.stringify(keys)))refuse('CONDITIONAL_SHAPE','Dictionary key sets/order differ');
      const children=keys.map((key,index)=>[key,build(live.map(n=>under(n.entries[index].node,strict(n.presence))))]);
      const value=Object.fromEntries(children.map(([key,child])=>[key,child.value]));
      if(JSON.stringify(Object.keys(value))!==JSON.stringify(keys))refuse('ORDER','String index keys cannot preserve source order through this input protocol');
      requirements.push(...children.map(([,child])=>child.ready));constraints.push({segments:first.segments,kind:'source-ordered-dictionary',keys});
      return {value,ready:combine(requirements)};
    }
    const length=first.items.length;if(live.some(n=>n.items.length!==length))refuse('CONDITIONAL_SHAPE','Array capacities differ');
    for(const n of live){const present=strict(n.presence),fits=fresh(`=IFERROR(IF(ISNUMBER(${n.length}),${n.length}=${length},FALSE),FALSE)`);requirements.push(fresh(`=IF(${present},${fits},TRUE)`));}
    const children=first.items.map((_,i)=>build(live.map(n=>under(n.items[i],strict(n.presence)))));requirements.push(...children.map(c=>c.ready));
    constraints.push({segments:first.segments,kind:'complete-source-array',length});return {value:children.map(c=>c.value),ready:combine(requirements)};
  };
  let selected=candidates;
  if(options.dictionaryKeys!==undefined){
    dataArray(options.dictionaryKeys,'dictionary view keys');const keys=options.dictionaryKeys;
    if(keys.some(k=>typeof k!=='string'||forbidden.has(k))||new Set(keys).size!==keys.length)refuse('STRUCTURE','invalid Dictionary view keys');
    const sorted=JSON.stringify([...keys].sort());selected=alternatives(candidates).filter(n=>n.kind==='dictionary'&&JSON.stringify(n.entries.map(e=>e.key).sort())===sorted);
    if(!selected.length)refuse('NO_OUTPUTS','requested complete Dictionary shape is absent from source');
    constraints.push({kind:'selected-source-dictionary-domain',keys:keys.slice()});
  }
  const built=build(selected),typeAdmissions=structuralTypes.map(({predicate,when})=>{const valid=fresh(`=IFERROR(ISLOGICAL(${predicate}),FALSE)`);return when?fresh(`=IF(${strict(when)},${valid},TRUE)`):valid;}),ready=combine([strict(adoption),strict(structure.availability),built.ready,...typeAdmissions]);
  return {schema:'canonical-gd-whole-composition-v1',value:built.value,readyCell:isCell(ready)?ready:fresh('='+ready),formulas,constraints,
    provenance:{graphSha256:proof.graphSha256,structureSha256:hash(structure),descriptorsSha256:hash(descriptors),adoption,sourceDerived:true},
    qualification:'Complete finite source-shape view only, under readyCell. Unknown order/category/shape refuses; shorter arrays make this view unavailable. No workbook/native/full-horizon qualification.'};
}
