/** Generic, predicated SSA/heap lowering of canonical-gd-model-ir-v1.
 * No financial function names/equations live here. Cells are ordinary scalar
 * formulas; containers and bounded control flow are specialized at authoring.
 *
 * emitExcel(IR, {entrypoint, arguments, inputs?, outputs?, helperSheet?,
 *   helperColumn?, helperStartRow?, maxCells?, maxArrayLength?}) returns data;
 * it never constructs, calculates, reads or writes a workbook. Argument/input
 * trees are finite JS dictionaries/arrays with literals or {cell,type} leaves.
 * Types are number/boolean/string/variant; numeric cells additionally carry
 * numericType:'int'|'float' when numeric provenance is needed. Missing numeric
 * provenance fails closed for typeof/division; never inferred from cell values.
 * Literal JS input numbers are unknown unless modelNumber-tagged or the caller
 * explicitly selects numericInputs:'float' (JSON-number domain). Source literals,
 * typed slots, casts and container mutations retain exact numeric tags.
 * Editable cells still receive typeof/is_finite checks. Optional entries use
 * {$optional:true,present:<Boolean leaf>,value:<leaf or container>}.
 * Output paths are state.field, state.array[0], etc. (scalar root: result).
 * `outputs` optionally maps those paths to admitted local destination cells;
 * other output formulas remain in the returned data, not helper cells.
 * The caller must reserve a free helper rectangle and bind canonical units.
 * Literal source numeric strings are supported; arbitrary editable text-number
 * validation is rejected rather than approximated with Excel coercion.
 * Nullable scalar outputs are unavailable (NA), never silently numeric zero.
 * Default structural optimization preserves ordered typed scalar expressions,
 * heap versions and all validation roots; optimize:false is a comparison mode,
 * not a validation bypass. Single-use packing caps formulas at 4096 characters
 * and 48 parenthesis levels. It reduces cells, not arithmetic-operation count.
 * EXACT is REQUIRED for editable text equality. The emitter performs no engine
 * qualification; applicable external capability evidence, whitelist integration
 * and full saved-file parity are separate caller obligations.
 * Source/IR/binding digests are attribution, not authenticated producer proof;
 * the parent must separately hash these modules in the build provenance.
 */
import { createHash } from 'node:crypto';
import { ModelCompileError, modelConstants, builtinValue, binaryValue, modelArithmetic, modelNumber, isModelNumber, rawNumber, numericKind, coerceTyped, gdType, variantType, VARIANT_TYPES, validFloatString, irFingerprint, COMPILER_VERSION } from './model-compiler.mjs';
export const EXCEL_BACKEND_VERSION='gd-excel-4';
const scalar=v=>v&&v.tag==='scalar';
const ref=v=>v&&v.tag==='ref';
const choice=v=>v&&v.tag==='choice';
const unprovedType=v=>v&&v.tag==='unproved-type-enum';
const ABSENT=Symbol('absent');
const primitive=v=>isModelNumber(v)||v===null||['number','boolean','string'].includes(typeof v);
const type=v=>unprovedType(v)?'number':scalar(v)?v.type:gdType(v);
// Bare backend bookkeeping constants are floats; source and input numbers are
// always tagged before reaching arithmetic. No value-based integer inference.
const numberType=v=>unprovedType(v)?'int':scalar(v)?v.numericType??'unknown':isModelNumber(v)?numericKind(v):typeof v==='number'?'float':'unknown';
const withNumberType=(v,kind)=>scalar(v)?{...v,numericType:kind,...(v.numericType!==kind?{phi:undefined}:{})}:modelNumber(rawNumber(v),kind);
const digest=v=>createHash('sha256').update(v).digest('hex');
const literal=value=>{const v=rawNumber(value);return v===ABSENT||v===undefined||v===null?'NA()':typeof v==='number'?(Number.isFinite(v)?Object.is(v,-0)?'0':String(v).toUpperCase():'NA()'):typeof v==='boolean'?(v?'TRUE':'FALSE'):`"${String(v).replaceAll('"','""')}"`;};
const code=v=>unprovedType(v)?(()=>{throw new ModelCompileError('typeof numeric alternative requires exact int/float provenance; cannot observe an unproved type enum');})():choice(v)?`IF(${code(v.condition)},${code(v.yes)},${code(v.no)})`:scalar(v)?v.code:ref(v)?(()=>{throw new ModelCompileError('container has no scalar cell representation');})():literal(v);
const sheets=['Policy Lab','Policy','Assumptions','Economy','Shocks'];
function localCell(address){
  if(typeof address!=='string')return false;
  const match=/^(?:'([^']+)'|([A-Za-z ]+))!\$?([A-Z]{1,3})\$?([1-9][0-9]*)$/.exec(address);
  return !!match&&sheets.includes(match[1]??match[2])&&[...match[3]].reduce((n,c)=>n*26+c.charCodeAt(0)-64,0)<=16384&&Number(match[4])<=1048576;
}
const normalizedCell=address=>address.replaceAll('$','').replaceAll("'",'');

export function emitExcel(ir,cellBindings={}){
  if(ir.schema!=='canonical-gd-model-ir-v1'||ir.compilerVersion!==COMPILER_VERSION)throw new ModelCompileError('unsupported canonical IR/compiler version');
  if(ir.irSha256!==irFingerprint(ir))throw new ModelCompileError('IR fingerprint mismatch; recompile the canonical source');
  if(cellBindings.numericInputs!==undefined&&cellBindings.numericInputs!=='float')throw new ModelCompileError('numericInputs must be explicit float (JSON-number domain); otherwise use modelNumber tags');
  const entrypoint=cellBindings.entrypoint??ir.entrypoints[0];
  const maxCells=cellBindings.maxCells??250000,maxArray=cellBindings.maxArrayLength??256,maxLoops=cellBindings.maxLoopIterations??10000;
  const sheet=cellBindings.helperSheet??'Economy',column=cellBindings.helperColumn??'B',firstRow=cellBindings.helperStartRow??2000;
  if(!localCell(`'${sheet}'!${column}${firstRow}`)||!Number.isInteger(firstRow))throw new ModelCompileError('helper binding must use an admitted local sheet/A1 address');
  const optimize=cellBindings.optimize!==false;
  let nextId=0,nextEvent=0,operations=0,cellCount=0,unavailable=false,cseHits=0,packedHelpers=0;const formulas={},sourceMap=[],diagnostics=[],coverage=new Set(),calls=new Set(),loopProofs=[],intern=new Map(),dominators=new Map(),conjuncts=new Map(),negations=new Map(),reservedInputs=new Set();
  const limit=()=>{if(++operations>(cellBindings.maxOperations??5000000))throw new ModelCompileError('symbolic operation limit exceeded; no partial program returned');};
  const error=(message,n)=>{throw new ModelCompileError(message,n?.source);};
  const start=performance.now();
  const ctx={heap:new Map(),owned:new Set(),env:{},active:true};
  const make=(kind,data,c=ctx)=>{const id=++nextId;c.heap.set(id,{kind,...data});c.owned.add(id);return {tag:'ref',id};};
  const dict=(entries,c=ctx)=>make('dictionary',{entries:new Map(entries)},c);
  const array=(items,c=ctx,length=items.length)=>{if(items.length>maxArray)error('finite array specialization exceeds maxArrayLength');return make('array',{items,length,origin:c.active,rankInfo:{base:items.length,events:[]}},c);};
  const cloneObject=o=>o.kind==='array'?{...o,items:o.items.slice()}:{...o,entries:new Map(o.entries)};
  const branch=(c,active)=>({heap:optimize?new Map(c.heap):new Map([...c.heap].map(([id,o])=>[id,cloneObject(o)])),owned:optimize?new Set():new Set(c.heap.keys()),env:{...c.env},active});
  const writable=(v,c)=>{if(!c.owned.has(v.id)){c.heap.set(v.id,cloneObject(c.heap.get(v.id)));c.owned.add(v.id);}return c.heap.get(v.id);};
  // Persistent guard DAG, NOT a transitive Set on every guard (quadratic memory
  // for long validation chains). A bounded memo only accelerates exact proofs.
  const ancestorMemo=new Map();
  const ancestors=v=>{const key=code(v);if(ancestorMemo.has(key))return ancestorMemo.get(key);const found=new Set(),pending=[v];while(pending.length){const next=pending.pop(),key=code(next);if(found.has(key))continue;found.add(key);pending.push(...conjuncts.get(key)??[]);}if(ancestorMemo.size>=64)ancestorMemo.delete(ancestorMemo.keys().next().value);ancestorMemo.set(key,found);return found;};
  const implies=(a,b)=>{if(b===true||a===b)return true;const have=ancestors(a),pending=[b];while(pending.length){const v=pending.pop();if(v===true||have.has(code(v)))continue;const parts=conjuncts.get(code(v));if(!parts)return false;pending.push(...parts);}return true;};
  const exclusive=(a,b)=>{if(a===false||b===false)return true;const aa=ancestors(a),bb=ancestors(b);for(const x of aa){const inverse=negations.get(x);if(inverse&&bb.has(code(inverse)))return true;}return false;};
  const rankingBound=objects=>{
    const capacity=objects.reduce((sum,o)=>sum+o.items.length,0);
    if(!optimize||objects.some(o=>!o.rankInfo))return {bound:capacity,capacity,kind:'finite-capacity'};
    // A clique of pairwise contradictory append predicates contributes at most
    // ONE element. This is a conservative source-path proof, not a financial
    // bound or an assumption about numeric signs. Pops are ignored (upper bound).
    const events=objects.flatMap(o=>o.rankInfo.events),groups=[];
    for(const event of events){const group=groups.find(g=>g.every(other=>exclusive(event.guard,other.guard)));if(group)group.push(event);else groups.push([event]);}
    const bound=Math.min(capacity,objects.reduce((sum,o)=>sum+o.rankInfo.base,0)+groups.length);
    return {bound,capacity,kind:'finite-append-exclusion',appendEvents:events.length,exclusiveGroups:groups.length};
  };
  const emit=(formula,resultType,c,n)=>{
    limit();if(c.active===false)return resultType==='boolean'?false:resultType==='string'?'':0;
    const fallback=resultType==='boolean'?'FALSE':resultType==='string'?'""':'0';
    const full=c.active===true?formula:`IF(${code(c.active)},${formula},${fallback})`;
    const key=resultType+':'+full;
    if(intern.has(key))return intern.get(key);
    const expressionKey=resultType+':'+formula;
    if(optimize){const dominating=(dominators.get(expressionKey)??[]).find(x=>implies(c.active,x.guard));if(dominating){cseHits++;return dominating.value;}}
    const row=firstRow+cellCount;
    if(row>1048576||cellCount>=maxCells)error('Excel helper-cell budget exceeded; no partial program returned',n);
    if(full.length>8191)error('Excel scalar formula exceeds 8192-character limit',n);
    const address=`'${sheet}'!${column}${row}`,value={tag:'scalar',type:resultType,code:address,guard:c.active,fallback:resultType==='boolean'?false:resultType==='string'?'':0};
    if(reservedInputs.has(normalizedCell(address)))error(`helper/input collision ${address}`,n);
    formulas[address]='='+full;cellCount++;intern.set(key,value);if(optimize){const entries=dominators.get(expressionKey)??[];entries.push({guard:c.active,value});dominators.set(expressionKey,entries);}sourceMap.push({cell:address,node:n?.id??null,source:n?.source??null,type:resultType,active:code(c.active)});return value;
  };
  const bool=(v,c,n)=>{
    if(primitive(v))return Boolean(rawNumber(v));
    if(ref(v))return true;
    if(choice(v))return select(v.condition,bool(v.yes,c,n),bool(v.no,c,n),c,n);
    if(v.type==='boolean')return v;
    if(v.type==='number')return emit(`${code(v)}<>0`,'boolean',c,n);
    if(v.type==='string')return emit(`${code(v)}<>""`,'boolean',c,n);
    if(v.type==='variant')return emit(`IF(ISLOGICAL(${code(v)}),${code(v)},IF(ISNUMBER(${code(v)}),${code(v)}<>0,IF(ISBLANK(${code(v)}),FALSE,${code(v)}<>"")))`,'boolean',c,n);
    error('truthiness has no scalar representation',n);
  };
  // Path predicates must not themselves be predicated by the previously
  // visited arm (otherwise NOT(false) can accidentally become false).
  const not=(v,c,n)=>{v=bool(v,c,n);if(typeof v==='boolean')return !v;if(optimize&&negations.has(code(v)))return negations.get(code(v));const result=emit(`NOT(${code(v)})`,'boolean',{...c,active:true},n);if(optimize){negations.set(code(result),v);negations.set(code(v),result);}return result;};
  const and=(a,b,c,n)=>{if(a===b)return a;if(a===false||b===false)return false;if(a===true)return b;if(b===true)return a;
    if(optimize){if(implies(a,b))return a;if(implies(b,a))return b;}
    const result=emit(`IF(${code(a)},${code(b)},FALSE)`,'boolean',{...c,active:true},n);if(optimize)conjuncts.set(code(result),[a,b]);return result;};
  const or=(a,b,c,n)=>a===b?a:a===true||b===true?true:a===false?b:b===false?a:emit(`IF(${code(a)},TRUE,${code(b)})`,'boolean',{...c,active:true},n);
  const markUnavailable=(c,n,guard=c.active)=>{if(guard===false)return;diagnostics.push({kind:'unavailable-guard',source:n?.source,node:n?.id,condition:code(guard)});unavailable=or(unavailable,guard,c,n);};
  const select=(condition,yes,no,c,n)=>{
    if(condition===true)return yes;if(condition===false)return no;
    if(yes===no||(ref(yes)&&ref(no)&&yes.id===no.id))return yes;
    // Distinct numeric tags are observable by later Variant division/typeof.
    // Keep a guarded choice, even when the numeric values/cell codes coincide.
    if(type(yes)==='number'&&type(no)==='number'&&numberType(yes)!==numberType(no))return {tag:'choice',condition,yes,no};
    if(optimize){
      if(yes===true&&no===false)return condition;
      if(yes===false&&no===true)return not(condition,c,n);
      if(yes===false&&type(no)==='boolean')return and(not(condition,c,n),no,c,n);
      if(no===false&&type(yes)==='boolean')return and(condition,yes,c,n);
      if(scalar(yes)&&scalar(no)&&yes.code===no.code&&yes.type===no.type)return yes;
      // Ordered scalar DAG identities only. Guarded values are already equal to
      // their fallback outside that guard, so a redundant outer phi is removed.
      if(scalar(yes)&&yes.guard!==true&&no===yes.fallback&&implies(yes.guard,condition))return yes;
      if(scalar(no)&&no.guard!==true&&yes===no.fallback&&implies(no.guard,not(condition,c,n)))return no;
      if(scalar(yes)&&yes.phi&&implies(condition,yes.phi.condition))yes=yes.phi.yes;
      if(scalar(no)&&no.phi&&implies(not(condition,c,n),not(no.phi.condition,c,n)))no=no.phi.no;
      if(yes===no)return yes;
    }
    if(yes===ABSENT&&no===ABSENT)return ABSENT;
    if(ref(yes)||ref(no)||choice(yes)||choice(no)||yes===ABSENT||no===ABSENT||yes===null||no===null)return {tag:'choice',condition,yes,no};
    const t=type(yes)===type(no)?type(yes):'variant',emitted=emit(`IF(${code(condition)},${code(yes)},${code(no)})`,t,{...c,active:true},n),result=t==='number'?withNumberType(emitted,numberType(yes)):emitted;if(optimize)result.phi={condition,yes,no};return result;
  };
  const numeric=(v,c,n)=>{
    if(primitive(v)){try{return modelNumber(builtinValue('float',[rawNumber(v)]),'float');}catch{return NaN;}}
    if(choice(v)){const saved=c.active;c.active=and(saved,v.condition,c,n);const a=numeric(v.yes,c,n);c.active=and(saved,not(v.condition,c,n),c,n);const b=numeric(v.no,c,n);c.active=saved;return select(v.condition,a,b,c,n);}
    if(!scalar(v)){markUnavailable(c,n);return 0;}
    if(v.type==='number')return withNumberType(v,'float');
    if(v.type==='boolean')return withNumberType(emit(`IF(${code(v)},1,0)`,'number',c,n),'float');
    return withNumberType(emit(`IFERROR(1*${code(v)},NA())`,'number',c,n),'float');
  };
  const unary=(op,v,c,n)=>{
    if(op==='not')return not(v,c,n);
    if(c.active===false)return modelNumber(0,'float');
    if(choice(v)){const saved=c.active;c.active=and(saved,v.condition,c,n);const a=unary(op,v.yes,c,n);c.active=and(saved,not(v.condition,c,n),c,n);const b=unary(op,v.no,c,n);c.active=saved;return select(v.condition,a,b,c,n);}
    if(v===ABSENT||v===null){markUnavailable(c,n);return modelNumber(0,'float');}
    if(!['number','variant'].includes(type(v)))error('Boolean/non-numeric unary arithmetic requires explicit conversion',n);
    if(scalar(v)&&(v.external||v.type==='variant'))markUnavailable(c,n,and(c.active,not(math('is_finite',[v],c,n),c,n),c,n));
    if(primitive(v))return modelNumber(op==='-'?-rawNumber(v):+rawNumber(v),numberType(v));
    return withNumberType(emit(`${op}(${code(v)})`,'number',c,n),numberType(v));
  };
  // Equality compares numeric int/float values across subtypes, while excluding
  // Boolean/text coercion. This internal category is NOT source-visible typeof.
  const category=(v,c,n)=>primitive(v)?gdType(v):ref(v)?c.heap.get(v.id).kind:!v.external&&v.type!=='variant'?v.type:emit(`IF(ISLOGICAL(${code(v)}),"boolean",IF(ISNUMBER(${code(v)}),"number",IF(ISBLANK(${code(v)}),"null","string")))`,'string',c,n);
  const compare=(op,a,b,c,n)=>{
    if(choice(a))return select(a.condition,compare(op,a.yes,b,c,n),compare(op,a.no,b,c,n),c,n);
    if(choice(b))return select(b.condition,compare(op,a,b.yes,c,n),compare(op,a,b.no,c,n),c,n);
    if(unprovedType(a)||unprovedType(b)){
      // A nonnumeric-schema cell may contain a number after an invalid edit.
      // We can prove it is NOT TYPE_BOOL/String/etc without guessing 2 vs 3.
      // Any observation which distinguishes the numeric alternatives refuses.
      const values=v=>unprovedType(v)?[2,3]:primitive(v)?[rawNumber(v)]:null,aa=values(a),bb=values(b);
      if(aa&&bb&&['==','!='].includes(op)){const results=aa.flatMap(x=>bb.map(y=>binaryValue(op,x,y)));if(results.every(x=>x===results[0]))return results[0];}
      error('typeof numeric alternative requires exact int/float provenance',n);
    }
    if(a===ABSENT||b===ABSENT)return op==='!=';
    if(primitive(a)&&primitive(b))return binaryValue(op,a,b);
    if(['==','!='].includes(op)&&type(a)!=='variant'&&type(b)!=='variant'&&type(a)!==type(b))return op==='!=';
    if(ref(a)||ref(b)){
      if(!ref(a)||!ref(b))return op==='!=';
      if(!['==','!='].includes(op))error('ordered container comparison unsupported',n);
      const aa=c.heap.get(a.id),bb=c.heap.get(b.id);let eq=true;
      if(aa.kind!==bb.kind)eq=false;
      else if(aa.kind==='array'){eq=compare('==',aa.length,bb.length,c,n);for(let i=0;i<Math.max(aa.items.length,bb.items.length);i++)eq=and(eq,or(not(compare('<',i,aa.length,c,n),c,n),compare('==',aa.items[i]??null,bb.items[i]??null,c,n),c,n),c,n);}
      else {const keys=new Set([...aa.entries.keys(),...bb.entries.keys()]);for(const k of keys){const a=aa.entries.get(k)??{present:false,value:ABSENT},b=bb.entries.get(k)??{present:false,value:ABSENT};eq=and(eq,and(compare('==',a.present,b.present,c,n),or(not(a.present,c,n),compare('==',a.value,b.value,c,n),c,n),c,n),c,n);}}
      return op==='=='?eq:not(eq,c,n);
    }
    if(typeof rawNumber(a)==='number'&&!Number.isFinite(rawNumber(a))||typeof rawNumber(b)==='number'&&!Number.isFinite(rawNumber(b))){
      const swapped=typeof rawNumber(a)==='number'&&!Number.isFinite(rawNumber(a)),constant=rawNumber(swapped?a:b),other=swapped?b:a;
      if(Number.isNaN(constant))return op==='!=';
      if(type(other)==='number')return binaryValue(op,swapped?constant:0,swapped?0:constant);
      error('nonfinite comparison requires a numeric operand',n);
    }
    const translated=({'==':'=','!=':'<>'})[op]??op;
    if(!['==','!='].includes(op)&&['string','variant'].some(t=>type(a)===t||type(b)===t))error('ordered editable text/Variant comparison has no qualified case-sensitive Unicode backend primitive',n);
    if(['==','!='].includes(op)&&(scalar(a)&&(a.external||a.type==='variant')||scalar(b)&&(b.external||b.type==='variant'))){
      const ta=category(a,c,n),tb=category(b,c,n),sameType=compare('==',ta,tb,c,n);
      const equal=and(sameType,select(compare('==',ta,'string',c,n),emit(`EXACT(${code(a)},${code(b)})`,'boolean',c,n),emit(`${code(a)}=${code(b)}`,'boolean',c,n),c,n),c,n);
      return op==='=='?equal:not(equal,c,n);
    }
    if(['==','!='].includes(op)&&(type(a)==='string'||type(b)==='string')){const equal=emit(`EXACT(${code(a)},${code(b)})`,'boolean',c,n);return op==='=='?equal:not(equal,c,n);}
    return emit(`${code(a)}${translated}${code(b)}`,'boolean',c,n);
  };
  const bin=(op,a,b,c,n)=>{
    if(c.active===false)return modelNumber(0,'float');
    if(choice(a)){const saved=c.active;c.active=and(saved,a.condition,c,n);const x=bin(op,a.yes,b,c,n);c.active=and(saved,not(a.condition,c,n),c,n);const y=bin(op,a.no,b,c,n);c.active=saved;return select(a.condition,x,y,c,n);}
    if(choice(b)){const saved=c.active;c.active=and(saved,b.condition,c,n);const x=bin(op,a,b.yes,c,n);c.active=and(saved,not(b.condition,c,n),c,n);const y=bin(op,a,b.no,c,n);c.active=saved;return select(b.condition,x,y,c,n);}
    if(['==','!=','<','>','<=','>='].includes(op))return compare(op,a,b,c,n);
    if(op==='in'||op==='not in'){
      let found=false;
      if(ref(b)){const o=c.heap.get(b.id);if(o.kind==='array'){o.items.forEach((v,i)=>{found=or(found,and(compare('<',i,o.length,c,n),compare('==',a,v,c,n),c,n),c,n);});}else{for(const [key,e] of o.entries)found=or(found,and(compare('==',a,key,c,n),e.present,c,n),c,n);}}
      else if(primitive(a)&&primitive(b))found=binaryValue('in',a,b);else error('membership requires a finite container or literal string',n);
      return op==='not in'?not(found,c,n):found;
    }
    if(a===ABSENT||b===ABSENT||a===null||b===null){markUnavailable(c,n);return modelNumber(0,'float');}
    if(primitive(a)&&primitive(b)){try{return modelArithmetic(op,isModelNumber(a)?a:typeof a==='number'?modelNumber(a,'float'):a,isModelNumber(b)?b:typeof b==='number'?modelNumber(b,'float'):b);}catch(e){error(e.message,n);}}
    if(op==='%'&&(typeof a==='string'))return format(a,b,c,n);
    if(op==='+'&&(type(a)==='string'||type(b)==='string')){
      if(type(a)!=='string'||type(b)!=='string')error('String arithmetic requires two String operands; use explicit conversion',n);
      for(const operand of [a,b])if(scalar(operand)&&operand.external)markUnavailable(c,n,and(c.active,not(compare('==',category(operand,c,n),'string',c,n),c,n),c,n));
      return emit(`${code(a)}&${code(b)}`,'string',c,n);
    }
    if(op==='is')error('dynamic is checks unsupported; use typeof',n);
    if(op==='%')error('dynamic numeric remainder has no admitted backend primitive',n);
    for(const operand of [a,b]){
      if(!['number','variant'].includes(type(operand)))error('Boolean/non-numeric arithmetic requires explicit conversion',n);
      if(scalar(operand)&&(operand.external||operand.type==='variant')){const valid=math('is_finite',[operand],c,n);markUnavailable(c,n,and(c.active,not(valid,c,n),c,n));}
    }
    const ka=numberType(a),kb=numberType(b),kind=ka==='float'||kb==='float'?'float':ka==='int'&&kb==='int'?'int':'unknown';
    if(op==='/'&&kind==='unknown')error('unproved Variant numeric division: bind exact numericType int/float or cast explicitly',n);
    if(op==='**'&&kind==='int')error('dynamic integer power is outside the proven numeric subset',n);
    const value=withNumberType(emit(op==='**'?`POWER(${code(a)},${code(b)})`:`(${code(a)}${op}${code(b)})`,'number',c,n),kind);return kind==='int'?typed(value,'int',c,n):value;
  };
  const get=(v,key,c,n,optional=false)=>{
    key=rawNumber(key);
    if(choice(v)){const saved=c.active;c.active=and(saved,v.condition,c,n);const a=get(v.yes,key,c,n,optional);c.active=and(saved,not(v.condition,c,n),c,n);const b=get(v.no,key,c,n,optional);c.active=saved;return optional?{present:select(v.condition,a.present,b.present,c,n),value:select(v.condition,a.value,b.value,c,n)}:select(v.condition,a,b,c,n);}
    if(v===ABSENT||v===null||typeof v==='number'&&Number.isNaN(v)){if(!optional)markUnavailable(c,n);return optional?{present:false,value:ABSENT}:0;}
    // A missing field on a rejected return arm stays unavailable. This does not
    // invent a successful value for invalid input/result paths.
    if(!ref(v)){if(!optional)markUnavailable(c,n);return optional?{present:false,value:ABSENT}:0;}
    const o=c.heap.get(v.id);
    if(o.kind==='dictionary'){
      if(primitive(key)){const e=o.entries.get(String(key))??{present:false,value:ABSENT};if(!optional)markUnavailable(c,n,and(c.active,not(e.present,c,n),c,n));return optional?e:select(e.present,e.value,0,c,n);}
      let value=ABSENT,present=false;for(const [k,e] of o.entries){const matches=and(compare('==',key,k,c,n),e.present,c,n);value=select(matches,e.value,value,c,n);present=or(present,matches,c,n);}if(!optional)markUnavailable(c,n,and(c.active,not(present,c,n),c,n));return optional?{value,present}:select(present,value,0,c,n);
    }
    let index=key;if(typeof index==='number'&&index<0)index=bin('+',o.length,index,c,n);else if(scalar(index))index=select(compare('<',index,0,c,n),bin('+',o.length,index,c,n),index,c,n);
    const valid=and(and(compare('>=',index,0,c,n),compare('<',index,o.length,c,n),c,n),compare('==',index,math('int',[index],c,n),c,n),c,n);
    let value;
    if(typeof index==='number')value=o.items[index]??ABSENT;
    else {const pick=(lo,hi)=>{if(lo===hi)return o.items[lo];const mid=Math.floor((lo+hi)/2);return select(compare('<=',index,mid,c,n),pick(lo,mid),pick(mid+1,hi),c,n);};value=o.items.length?pick(0,o.items.length-1):ABSENT;}
    if(!optional)markUnavailable(c,n,and(c.active,not(valid,c,n),c,n));return optional?{present:valid,value}:select(valid,value===ABSENT?0:value,0,c,n);
  };
  const put=(v,key,value,c,n,guard=c.active)=>{
    key=rawNumber(key);
    if(choice(v)){put(v.yes,key,value,c,n,and(guard,v.condition,c,n));put(v.no,key,value,c,n,and(guard,not(v.condition,c,n),c,n));return;}
    if(guard===false)return;
    if(!ref(v)){markUnavailable(c,n,guard);return;}
    const o=writable(v,c);
    if(o.kind==='dictionary'){
      if(!primitive(key)){
        error('dynamic dictionary output key has no finite literal key schema',n);
      }
      const old=o.entries.get(String(key))??{present:false,value:ABSENT};o.entries.set(String(key),{present:or(guard,old.present,c,n),value:select(guard,value,old.value,c,n)});return;
    }
    let index=key;if(typeof index==='number'&&index<0)index=bin('+',o.length,index,c,n);else if(scalar(index))index=select(compare('<',index,0,c,n),bin('+',o.length,index,c,n),index,c,n);
    const valid=and(and(compare('>=',index,0,c,n),compare('<',index,o.length,c,n),c,n),compare('==',index,math('int',[index],c,n),c,n),c,n);
    markUnavailable(c,n,and(guard,not(valid,c,n),c,n));guard=and(guard,valid,c,n);
    if(typeof index==='number'){if(!Number.isInteger(index)||index<0||index>=o.items.length)return;o.items[index]=select(guard,value,o.items[index],c,n);}
    else o.items=o.items.map((old,i)=>select(and(guard,compare('==',index,i,c,n),c,n),value,old,c,n));
  };
  const mergeHeap=(target,a,b,condition,n)=>{
    const all=new Set([...a.heap.keys(),...b.heap.keys()]);const heap=new Map();target.heap=heap;target.owned=new Set();
    for(const id of all){const x=a.heap.get(id),y=b.heap.get(id);if(!x||!y||optimize&&x===y){heap.set(id,x??y);continue;}if(x.kind!==y.kind)error('heap object changed kind',n);
      // Only the new merged objects below are owned. Borrowed/shared objects
      // above may still belong to an outer sibling and must copy on first write.
      target.owned.add(id);
      if(x.kind==='array')heap.set(id,{kind:'array',origin:x.origin===y.origin?x.origin:null,rankInfo:x.rankInfo&&y.rankInfo&&x.rankInfo.base===y.rankInfo.base?{base:x.rankInfo.base,events:[...new Map([...x.rankInfo.events,...y.rankInfo.events].map(e=>[e.id,e])).values()]}:null,length:select(condition,x.length,y.length,target,n),items:Array.from({length:Math.max(x.items.length,y.items.length)},(_,i)=>select(condition,i<x.items.length?x.items[i]:0,i<y.items.length?y.items[i]:0,target,n))});
      else {const entries=new Map();for(const k of new Set([...x.entries.keys(),...y.entries.keys()])){const xx=x.entries.get(k)??{present:false,value:ABSENT},yy=y.entries.get(k)??{present:false,value:ABSENT};entries.set(k,{present:select(condition,xx.present,yy.present,target,n),value:select(condition,xx.value,yy.value,target,n)});}heap.set(id,{kind:'dictionary',entries});}}
  };
  const mergeContexts=(target,a,b,condition,n)=>{
    mergeHeap(target,a,b,condition,n);const env={};for(const k of new Set([...Object.keys(a.env),...Object.keys(b.env)]))env[k]=select(condition,a.env[k]??ABSENT,b.env[k]??ABSENT,target,n);target.env=env;target.active=or(a.active,b.active,target,n);
  };
  const math=(name,args,c,n)=>{
    const alternative=args.findIndex(choice);if(alternative>=0){const v=args[alternative],saved=c.active;c.active=and(saved,v.condition,c,n);const a=math(name,args.map((x,i)=>i===alternative?v.yes:x),c,n);c.active=and(saved,not(v.condition,c,n),c,n);const b=math(name,args.map((x,i)=>i===alternative?v.no:x),c,n);c.active=saved;return select(v.condition,a,b,c,n);}
    if(name==='typeof'){
      const v=args[0];if(choice(v))return select(v.condition,math(name,[v.yes],c,n),math(name,[v.no],c,n),c,n);
      if(unprovedType(v))return modelNumber(VARIANT_TYPES.TYPE_INT,'int');
      if(v===ABSENT){markUnavailable(c,n);return modelNumber(VARIANT_TYPES.TYPE_NIL,'int');}
      if(ref(v))return modelNumber(c.heap.get(v.id).kind==='array'?VARIANT_TYPES.TYPE_ARRAY:VARIANT_TYPES.TYPE_DICTIONARY,'int');
      if(primitive(v)){try{return modelNumber(variantType(isModelNumber(v)?v:typeof v==='number'?modelNumber(v,numberType(v)):v),'int');}catch(e){error(e.message,n);}}
      if((v.type==='number'||v.type==='variant')&&numberType(v)==='unknown')error('typeof numeric cell requires exact numericType int/float provenance',n);
      if(v.type!=='variant'&&!v.external)return modelNumber(v.type==='number'?(numberType(v)==='int'?2:3):v.type==='boolean'?1:4,'int');
      // These closed predicates are total even for spreadsheet error cells.
      // Hoisting them changes no lazy error behavior and enables exact reuse
      // across validation paths; no economic arithmetic is hoisted.
      const total=optimize?{...c,active:true}:c;
      const valid=emit(`IFERROR(${code(v)}=${code(v)},FALSE)`,'boolean',total,n);markUnavailable(c,n,and(c.active,not(valid,c,n),c,n));
      if(numberType(v)==='unknown'){
        const isNumber=emit(`ISNUMBER(${code(v)})`,'boolean',total,n);
        const nonnumeric=withNumberType(emit(`IF(ISLOGICAL(${code(v)}),1,IF(ISBLANK(${code(v)}),0,4))`,'number',total,n),'int');
        return {tag:'choice',condition:isNumber,yes:{tag:'unproved-type-enum'},no:nonnumeric};
      }
      return withNumberType(emit(`IF(ISLOGICAL(${code(v)}),1,IF(ISNUMBER(${code(v)}),${numberType(v)==='int'?2:3},IF(ISBLANK(${code(v)}),0,4)))`,'number',total,n),'int');
    }
    if(['pow','abs','min','max','minf','maxf','clamp','exp','log','tanh','lerpf','round','roundf','signf','floor'].includes(name)){
      if(c.active===false)return modelNumber(0,'float');
      for(const v of args){
        if(v===null||v===ABSENT){markUnavailable(c,n);return NaN;}
        if(!['number','variant'].includes(type(v)))error('Boolean/non-numeric math requires explicit numeric conversion',n);
        if(scalar(v)&&(v.external||v.type==='variant'))markUnavailable(c,n,and(c.active,not(math('is_finite',[v],c,n),c,n),c,n));
      }
    }
    const kinds=args.map(numberType),resultKind=name==='int'?'int':name==='float'||['pow','exp','log','tanh','lerpf','minf','maxf','roundf','signf'].includes(name)?'float':kinds.every(k=>k==='int')?'int':kinds.every(k=>k==='float')?'float':'unknown';
    if(args.every(primitive)){try{const value=builtinValue(name,args.map(rawNumber),maxLoops);return Array.isArray(value)?array(value.map(x=>modelNumber(x,'int')),c):typeof value==='number'?modelNumber(value,resultKind):value;}catch(error){if(name==='range')throw error;return NaN;}}
    if(name==='is_finite'){const v=args[0];return ref(v)?false:emit(`IFERROR(IF(ISLOGICAL(${code(v)}),FALSE,ISNUMBER(${code(v)})),FALSE)`,'boolean',optimize?{...c,active:true}:c,n);}
    if(name==='float')return numeric(args[0],c,n);
    if(name==='int'){
      const value=numeric(args[0],c,n),result=emit(`SIGN(${code(value)})*INT(ABS(${code(value)}))`,'number',c,n),valid=compare('<=',math('abs',[result],c,n),Number.MAX_SAFE_INTEGER,c,n);
      markUnavailable(c,n,and(c.active,not(valid,c,n),c,n));return withNumberType(result,'int');
    }
    if(name==='str')return emit(`${code(args[0])}&""`,'string',c,n);
    if(name==='range')error('range bound must specialize to finite integers, not an editable scalar',n);
    if(name==='lerpf'){
      // The intrinsic signature is (float,float,float)->float. Do not let
      // integer source literals/tags change its ordered intermediate arithmetic.
      const [from,to,weight]=args.map(v=>withNumberType(v,'float'));
      return withNumberType(bin('+',from,bin('*',bin('-',to,from,c,n),weight,c,n),c,n),'float');
    }
    if(name==='clamp')return math('min',[args[2],math('max',[args[1],args[0]],c,n)],c,n);
    if(name==='round'||name==='roundf')return withNumberType(emit(`SIGN(${code(args[0])})*ROUND(ABS(${code(args[0])}),0)`,'number',c,n),resultKind);
    const op=({pow:'POWER',abs:'ABS',min:'MIN',minf:'MIN',max:'MAX',maxf:'MAX',exp:'EXP',log:'LN',tanh:'TANH',floor:'INT',signf:'SIGN'})[name];
    if(!op)error(`unsupported builtin ${name}`,n);return withNumberType(emit(`${op}(${args.map(code).join(',')})`,'number',c,n),resultKind);
  };
  const typed=(v,target,c,n)=>{
    if(!target||target==='Variant'||target==='void')return v;
    if(choice(v)){const saved=c.active;c.active=and(saved,v.condition,c,n);const a=typed(v.yes,target,c,n);c.active=and(saved,not(v.condition,c,n),c,n);const b=typed(v.no,target,c,n);c.active=saved;return select(v.condition,a,b,c,n);}
    if(primitive(v)){try{const value=coerceTyped(v,target);return ['int','float'].includes(target)?modelNumber(value,target):value;}catch{markUnavailable(c,n);c.active=false;return 0;}}
    if(target==='int'||target==='float'){
      if(!scalar(v)){markUnavailable(c,n);c.active=false;return 0;}
      if(v.type!=='number'||v.external){const valid=math('is_finite',[v],c,n);markUnavailable(c,n,and(c.active,not(valid,c,n),c,n));c.active=and(c.active,valid,c,n);}
      if(target==='float')return withNumberType(v,'float');
      return math('int',[v],c,n);
    }
    const expected=({bool:'boolean',String:'string',Array:'array',Dictionary:'dictionary'})[target];
    const actual=category(v,c,n),valid=compare('==',actual,expected,c,n);
    markUnavailable(c,n,and(c.active,not(valid,c,n),c,n));c.active=and(c.active,valid,c,n);return v;
  };
  const format=(template,value,c,n)=>{
    const values=ref(value)&&c.heap.get(value.id).kind==='array'?c.heap.get(value.id).items:[value];let i=0;const parts=[];let last=0;
    for(const match of template.matchAll(/%(?:\.(\d+))?([sdf%])/g)){
      parts.push(template.slice(last,match.index));last=match.index+match[0].length;
      if(match[2]==='%'){parts.push('%');continue;}const v=values[i++];
      if(primitive(v)){parts.push(binaryValue('%',match[0],v));continue;}
      if(match[2]==='s'){parts.push(v);continue;}if(match[2]==='d'){parts.push(math('int',[v],c,n));continue;}
      const digits=Number(match[1]??6);if(digits>12)error('numeric message precision exceeds scalar backend limit',n);
      const magnitude=math('round',[bin('*',math('abs',[v],c,n),10**digits,c,n)],c,n);
      parts.push(select(compare('<',v,0,c,n),'-','',c,n),math('floor',[bin('/',magnitude,10**digits,c,n)],c,n));
      if(digits)parts.push('.');for(let k=digits-1;k>=0;k--)parts.push(bin('-',math('floor',[bin('/',magnitude,10**k,c,n)],c,n),bin('*',10,math('floor',[bin('/',magnitude,10**(k+1),c,n)],c,n),c,n),c,n));
    }
    parts.push(template.slice(last));return parts.reduce((a,b)=>primitive(a)&&primitive(b)?String(a)+String(b):emit(`${code(a)}&${code(b)}`,'string',c,n),'');
  };
  const method=(object,name,args,c,n)=>{
    const invalid=()=>{markUnavailable(c,n);c.active=false;return ['get','size','pop_front','pop_back'].includes(name)?0:['has','is_empty'].includes(name)?false:['slice','duplicate','keys','values'].includes(name)?ABSENT:null;};
    if(object===ABSENT||object===null||typeof object==='number'&&Number.isNaN(object))return invalid();
    if(choice(object)){
      const a=branch(c,and(c.active,object.condition,c,n)),b=branch(c,and(c.active,not(object.condition,c,n),c,n));
      const x=method(object.yes,name,args,a,n),y=method(object.no,name,args,b,n);mergeContexts(c,a,b,object.condition,n);return select(object.condition,x,y,c,n);
    }
    if(['merge','append_array'].includes(name)&&choice(args[0])){const v=args[0],a=branch(c,and(c.active,v.condition,c,n)),b=branch(c,and(c.active,not(v.condition,c,n),c,n));const x=method(object,name,[v.yes,...args.slice(1)],a,n),y=method(object,name,[v.no,...args.slice(1)],b,n);mergeContexts(c,a,b,v.condition,n);return select(v.condition,x,y,c,n);}
    if(name==='is_valid_float'){
      if(typeof object==='string')return validFloatString(object);
      error('is_valid_float requires a literal source string; the admitted Excel dialect cannot validate arbitrary editable decimal text',n);
    }
    if(!ref(object))return invalid();
    const o=['merge','resize','fill','append_array','append','pop_back','pop_front','sort'].includes(name)?writable(object,c):c.heap.get(object.id);
    if(name==='get'||name==='has'){const e=get(object,args[0],c,n,true);return name==='has'?e.present:select(e.present,e.value,args[1]??null,c,n);}
    if(name==='size'||name==='is_empty'){const length=o.kind==='array'?o.length:[...o.entries.values()].reduce((sum,e)=>bin('+',sum,numeric(e.present,c,n),c,n),0);return name==='size'?withNumberType(length,'int'):compare('==',length,0,c,n);}
    if(name==='keys'||name==='values'){
      if(o.kind!=='dictionary')error(`${name} requires a dictionary`,n);
      if([...o.entries.values()].some(e=>e.present!==true))error('iteration over conditionally present dictionary keys needs explicit shape specialization',n);
      return array([...o.entries].map(([k,e])=>name==='keys'?k:e.value),c);
    }
    if(name==='duplicate'){
      if(args.length&&typeof args[0]!=='boolean')error('duplicate deep flag must specialize to a Boolean literal',n);
      const copy=(v,memo=new Map())=>{
        // A choice is not an immutable leaf: its container alternatives must be
        // disconnected too. One memo preserves sharing *within* the deep copy.
        if(choice(v))return {...v,yes:copy(v.yes,memo),no:copy(v.no,memo)};
        if(!ref(v))return v;if(memo.has(v.id))return memo.get(v.id);const q=c.heap.get(v.id),r=q.kind==='array'?array([],c):dict([],c);memo.set(v.id,r);const target=c.heap.get(r.id);if(q.kind==='array'){target.length=q.length;target.rankInfo=q.rankInfo;target.items=q.items.map(x=>args[0]?copy(x,memo):x);}else target.entries=new Map([...q.entries].map(([k,e])=>[k,{...e,value:args[0]?copy(e.value,memo):e.value}]));return r;
      };return copy(object);
    }
    if(name==='merge'){
      const other=c.heap.get(args[0]?.id);if(o.kind!=='dictionary'||other?.kind!=='dictionary'){markUnavailable(c,n);c.active=false;return null;}
      for(const [key,e] of other.entries){const old=o.entries.get(key)??{present:false,value:ABSENT},write=and(c.active,and(e.present,or(bool(args[1]??false,c,n),not(old.present,c,n),c,n),c,n),c,n);put(object,key,e.value,c,n,write);}return null;
    }
    if(o.kind!=='array')error(`array method ${name} on dictionary`,n);
    if(name==='slice'){
      const bounds=args.map(rawNumber);if(typeof o.length!=='number'||!bounds.every(x=>typeof x==='number'))error('slice requires statically finite bounds',n);
      return array(o.items.slice(...bounds),c);
    }
    if(name==='resize'){
      const length=rawNumber(args[0]);if(!Number.isSafeInteger(length)||length<0||length>maxArray)error('resize bound must be a finite specialization integer',n);
      const items=Array.from({length},(_,i)=>i<o.items.length?o.items[i]:null);
      if(c.active===true||c.active===o.origin){o.items=items;o.length=length;o.rankInfo={base:length,events:[]};}
      else {o.items=Array.from({length:Math.max(length,o.items.length)},(_,i)=>select(c.active,i<items.length?items[i]:0,i<o.items.length?o.items[i]:0,c,n));o.length=select(c.active,length,o.length,c,n);o.rankInfo=null;}return null;
    }
    if(name==='fill'){o.items=o.items.map(old=>c.active===o.origin?args[0]:select(c.active,args[0],old,c,n));return null;}
    if(name==='append_array'){const q=c.heap.get(args[0]?.id);if(q?.kind!=='array'||typeof q.length!=='number')error('append_array requires a finite source',n);for(let i=0;i<q.length;i++)method(object,'append',[q.items[i]],c,n);return null;}
    if(name==='append'){
      if(o.rankInfo)o.rankInfo={base:o.rankInfo.base,events:o.rankInfo.events.concat({id:++nextEvent,guard:c.active})};
      if(typeof o.length==='number'&&(c.active===true||c.active===o.origin)){o.items[o.length]=args[0];o.length++;}
      else {const capacity=o.items.length+1;if(capacity>maxArray)error('append bound exceeds finite specialization limit',n);o.items.push(0);o.items=o.items.map((old,i)=>select(and(c.active,compare('==',o.length,i,c,n),c,n),args[0],old,c,n));o.length=select(c.active,bin('+',o.length,1,c,n),o.length,c,n);}
      if(o.items.length>maxArray)error('array capacity exceeds finite specialization limit',n);return null;
    }
    if(name==='pop_back'||name==='pop_front'){
      const result=get(object,name==='pop_back'?bin('-',o.length,1,c,n):0,c,n);
      if(typeof o.length==='number'&&c.active===true){if(o.length===0)error('pop from empty finite array',n);if(name==='pop_back')o.items.pop();else o.items.shift();o.length--;}
      else {if(name==='pop_front')o.items=o.items.map((old,i)=>select(c.active,i+1<o.items.length?o.items[i+1]:0,old,c,n));o.length=select(c.active,bin('-',o.length,1,c,n),o.length,c,n);}return result;
    }
    if(name==='sort'){
      // Stable insertion network, including symbolic active lengths. This is a
      // generic Array.sort lowering, not an economic cancellation shortcut.
      for(let i=1;i<o.items.length;i++)for(let j=i;j>0;j--){const swap=and(c.active,and(compare('<',j,o.length,c,n),compare('>',o.items[j-1],o.items[j],c,n),c,n),c,n),a=o.items[j-1],b=o.items[j];o.items[j-1]=select(swap,b,a,c,n);o.items[j]=select(swap,a,b,c,n);}return null;
    }
    error(`unsupported finite-container method ${name}`,n);
  };
  const expression=(n,c)=>{limit();coverage.add(n.id);if(c.active===false)return null;
    switch(n.kind){case 'literal':return typeof n.value==='number'?modelNumber(n.value,n.type):n.value;case 'name':if(Object.hasOwn(c.env,n.name))return c.env[n.name];if(Object.hasOwn(globals,n.name))return globals[n.name];error(`unbound name ${n.name}`,n);break;
      case 'array':return array(n.items.map(x=>expression(x,c)),c);case 'dictionary':return dict(n.entries.map(({key,value})=>{const k=expression(key,c);if(!primitive(k))error('dictionary literal key must specialize to a literal',key);return [String(k),{present:true,value:expression(value,c)}];}),c);
      case 'member':return get(expression(n.object,c),n.name,c,n);case 'index':return get(expression(n.object,c),expression(n.index,c),c,n);
      case 'unary':return unary(n.op,expression(n.value,c),c,n);
      case 'binary':{const a=expression(n.left,c);if(n.op==='and'||n.op==='or'){const condition=bool(a,c,n);if(n.op==='and'&&condition===false||n.op==='or'&&condition===true)return condition;const saved=c.active;c.active=and(saved,n.op==='and'?condition:not(condition,c,n),c,n);const b=expression(n.right,c);c.active=saved;return n.op==='and'?and(condition,bool(b,c,n),c,n):or(condition,bool(b,c,n),c,n);}return bin(n.op,a,expression(n.right,c),c,n);}
      case 'conditional':{const condition=bool(expression(n.condition,c),c,n);if(typeof condition==='boolean')return expression(condition?n.yes:n.no,c);const a=branch(c,and(c.active,condition,c,n)),b=branch(c,and(c.active,not(condition,c,n),c,n));const x=expression(n.yes,a),y=expression(n.no,b);mergeContexts(c,a,b,condition,n);return select(condition,x,y,c,n);}
      case 'call':{const callee=n.callee;
        // Evaluate the receiver before arguments, preserving source order.
        const receiver=callee.kind==='member'?expression(callee.object,c):null,args=n.args.map(x=>expression(x,c));
        return callee.kind==='member'?method(receiver,callee.name,args,c,n):ir.functions[callee.name]||ir.boundaries[callee.name]?call(callee.name,args,c,n):math(callee.name,args,c,n);}
      default:error(`unsupported expression ${n.kind}`,n);
    }
  };
  const location=(target,c,n)=>{if(target.kind==='name')return {read:()=>c.env[target.name],write:value=>{c.env[target.name]=select(c.active,value,c.env[target.name]??ABSENT,c,n);}};const object=expression(target.object,c),key=target.kind==='member'?target.name:expression(target.index,c);return {read:()=>get(object,key,c,n),write:value=>put(object,key,value,c,n)};};
  const statements=(body,c,returns)=>{
    for(const n of body){limit();if(c.active===false)break;coverage.add(n.id);
      switch(n.kind){
        case 'declare':{const value=n.value?expression(n.value,c):null;c.env[n.name]=typed(value,n.storageType,c,n);break;}
        case 'assign':{const target=location(n.target,c,n),v=n.op==='='?expression(n.value,c):bin(n.op[0],target.read(),expression(n.value,c),c,{...n,type:n.operationType});target.write(typed(v,n.storageType,c,n));break;}
        case 'expression':expression(n.value,c);break;
        case 'return':{const value=expression(n.value,c);returns.push({guard:c.active,value,source:n.source});c.active=false;break;}
        case 'if':{const condition=bool(expression(n.condition,c),c,n);if(typeof condition==='boolean'){statements(condition?n.yes:n.no,c,returns);break;}const a=branch(c,and(c.active,condition,c,n)),b=branch(c,and(c.active,not(condition,c,n),c,n));statements(n.yes,a,returns);statements(n.no,b,returns);mergeContexts(c,a,b,condition,n);break;}
        case 'for':{const v=expression(n.iterable,c);const iterate=(v,c)=>{if(choice(v)){const a=branch(c,and(c.active,v.condition,c,n)),b=branch(c,and(c.active,not(v.condition,c,n),c,n));iterate(v.yes,a);iterate(v.no,b);mergeContexts(c,a,b,v.condition,n);return;}if(!ref(v)){markUnavailable(c,n);c.active=false;return;}const o=c.heap.get(v.id);let items;
          if(o.kind==='dictionary')items=[...o.entries.keys()];
          else items=o.items.slice();if(items.length>maxLoops)error('for loop exceeds specialization budget',n);loopProofs.push({node:n.id,iterations:items.length,kind:'finite-container'});
          const initialLength=o.length,initialKeys=o.kind==='dictionary'?[...o.entries].map(([key,e])=>[key,e.present]):null;
          for(let i=0;i<items.length&&c.active!==false;i++){
            const live=c.heap.get(v.id),saved=c.active,present=live.kind==='array'?compare('<',i,live.length,c,n):live.entries.get(items[i]).present;
            c.active=and(saved,present,c,n);c.env[n.name]=live.kind==='array'?live.items[i]:items[i];statements(n.body,c,returns);
            const after=c.heap.get(v.id);
            if(after.kind==='array'&&after.length!==initialLength)error('for iterable is resized/mutated: no finite iteration proof',n);
            if(after.kind==='dictionary'&&(after.entries.size!==initialKeys.length||initialKeys.some(([key,present])=>after.entries.get(key)?.present!==present)))error('for dictionary key set is mutated: no finite iteration proof',n);
            c.active=and(saved,or(not(present,c,n),c.active,c,n),c,n);
          }};iterate(v,c);break;}
        case 'while':{
          if(n.proof?.kind!=='decreasing-array-length')error('unproved while loop',n);
          const rankingIds=new Set(),rankingObjects=[];for(const name of n.proof.arrays){const v=c.env[name];if(!ref(v)||c.heap.get(v.id).kind!=='array')error('while ranking argument has no finite array shape',n);if(rankingIds.has(v.id))error('while ranking arrays alias: no independent length proof',n);rankingIds.add(v.id);rankingObjects.push(c.heap.get(v.id));}
          const sizeProof=rankingBound(rankingObjects),bound=Math.ceil(sizeProof.bound/-n.proof.maximumDelta);
          if(bound>maxLoops)error('while bound exceeds specialization budget',n);loopProofs.push({node:n.id,iterations:bound,kind:n.proof.kind,sizeProof});
          for(let i=0;i<bound&&c.active!==false;i++){
            const saved=c.active,condition=bool(expression(n.condition,c),c,n);if(condition===false)break;
            c.active=and(saved,condition,c,n);statements(n.body,c,returns);c.active=and(saved,or(not(condition,c,n),c.active,c,n),c,n);
          }
          // Defense in depth: even a compiler-proof regression must not silently
          // truncate a still-live loop into a successful result.
          const remaining=bool(expression(n.condition,c),c,n);markUnavailable(c,n,and(c.active,remaining,c,n));
          break;
        }
        case 'pass':break;default:error(`unsupported statement ${n.kind}`,n);
      }
    }
  };
  const input=(v,c)=>{
    if(isModelNumber(v))return v;
    if(v&&typeof v==='object'&&!Array.isArray(v)&&Object.hasOwn(v,'cell')){
      if(!localCell(v.cell))error('input binding must be one admitted local A1 cell');reservedInputs.add(normalizedCell(v.cell));
      if(!['number','boolean','string','variant'].includes(v.type))error('cell binding requires number/boolean/string/variant type');
      if(v.numericType!==undefined&&!['int','float'].includes(v.numericType))error('numericType must be explicit int or float');
      if(v.numericType!==undefined&&!['number','variant'].includes(v.type))error('numericType is only valid on number/variant bindings');
      const result={tag:'scalar',type:v.type,numericType:v.numericType??'unknown',code:v.cell,external:true};
      if(v.numericType==='int'){
        // A declared integer tag is a contract, not permission to guess/truncate
        // fractional cell data. Variant's nonnumeric alternatives stay allowed.
        const valid=emit(`IFERROR(IF(ISNUMBER(${v.cell}),IF(ABS(${v.cell})<=9007199254740991,${v.cell}=SIGN(${v.cell})*INT(ABS(${v.cell})),FALSE),${v.type==='variant'?'TRUE':'FALSE'}),FALSE)`,'boolean',c);
        markUnavailable(c,null,and(c.active,not(valid,c),c));
      }
      return result;
    }
    if(Array.isArray(v))return array(v.map(x=>input(x,c)),c);
    if(v&&typeof v==='object')return dict(Object.entries(v).map(([key,value])=>{
      if(value&&typeof value==='object'&&value.$optional===true){if(Object.keys(value).sort().join(',')!=='$optional,present,value')error('optional binding requires exactly $optional/present/value');const present=input(value.present,c);if(typeof present!=='boolean'&&(!scalar(present)||present.type!=='boolean'))error('optional presence needs a Boolean binding');return [key,{present,value:input(value.value,c)}];}
      return [key,{present:true,value:input(value,c)}];
    }),c);
    if(!primitive(v))error('unsupported input shape');return typeof v==='number'?modelNumber(v,cellBindings.numericInputs??'unknown'):v;
  };
  const globals=Object.fromEntries(Object.entries(modelConstants(ir,{preserveNumericTypes:true})).map(([k,v])=>[k,input(v,ctx)]));
  Object.assign(globals,{true:true,false:false,null:null,INF:Infinity,NAN:NaN,...Object.fromEntries(Object.entries(VARIANT_TYPES).map(([name,value])=>[name,modelNumber(value,'int')]))});
  const boundaryInputs=Object.fromEntries(Object.entries(cellBindings.inputs??{}).map(([k,v])=>[k,input(v,ctx)]));
  const call=(name,args,c,n)=>{
    calls.add(name);const boundary=ir.boundaries[name];
    if(boundary){if(!Object.hasOwn(boundaryInputs,boundary.input))error(`missing named input-only boundary ${boundary.input}`,n);const value=boundaryInputs[boundary.input],validation=call(boundary.validator,[value],c,n),ok=get(validation,'ok',c,n);return select(ok,dict([['ok',{present:true,value:true}],['value',{present:true,value}]],c),validation,c,n);}
    const fn=ir.functions[name];if(!fn)error(`unresolved function ${name}`,n);if(args.length>fn.params.length)error(`too many arguments to ${name}`,n);
    const local={heap:c.heap,owned:c.owned,env:{},active:c.active},returns=[];
    fn.params.forEach((p,i)=>{if(i<args.length)local.env[p.name]=typed(args[i],p.type,local,n??fn);else if(p.value)local.env[p.name]=typed(expression(p.value,local),p.type,local,n??fn);else error(`missing argument ${name}.${p.name}`,n??fn);});
    statements(fn.body,local,returns);c.heap=local.heap;c.owned=local.owned;
    for(const r of returns)diagnostics.push({kind:'return-arm',function:name,source:r.source,condition:code(r.guard)});
    if(!['void','Variant'].includes(fn.returns))markUnavailable(c,n??fn,local.active);
    // A sole return which covers the complete call domain needs no invented
    // absent/zero arm. Caller branches and output presence still guard its use.
    if(optimize&&returns.length===1&&implies(c.active,returns[0].guard))return typed(returns[0].value,fn.returns,{...c,active:returns[0].guard},n??fn);
    let value=fn.returns==='bool'?false:['float','int'].includes(fn.returns)?0:fn.returns==='String'?'':['Array','Dictionary'].includes(fn.returns)?ABSENT:null;
    for(let i=returns.length-1;i>=0;i--){const arm={...c,active:returns[i].guard};value=select(returns[i].guard,typed(returns[i].value,fn.returns,arm,n??fn),value,c,n??fn);}return value;
  };
  const fn=ir.functions[entrypoint];if(!fn)error(`unknown entrypoint ${entrypoint}`);
  const args=fn.params.map(p=>Object.hasOwn(cellBindings.arguments??{},p.name)?input(cellBindings.arguments[p.name],ctx):p.value?expression(p.value,ctx):error(`missing cellBindings.arguments.${p.name}`,fn));
  const result=call(entrypoint,args,ctx,fn),outputs={},outputPresence={};
  const flatten=(v,path,present=true,seen=new Set())=>{
    const leaves=new Map();
    if(unprovedType(v))error('typeof numeric alternative requires exact int/float provenance; output cannot observe an unproved type enum',fn);
    if(choice(v)){
      const a=flatten(v.yes,path,present,new Set(seen)),b=flatten(v.no,path,present,new Set(seen));
      for(const key of new Set([...a.keys(),...b.keys()])){const x=a.get(key)??{value:0,present:false},y=b.get(key)??{value:0,present:false};
        // A missing leaf is never observable: presence remains a mandatory
        // output guard. Do not manufacture a zero-valued phi for absent arms.
        const value=optimize&&x.present===false?y.value:optimize&&y.present===false?x.value:select(v.condition,x.value,y.value,ctx,fn);
        leaves.set(key,{value,present:select(v.condition,x.present,y.present,ctx,fn)});}return leaves;
    }
    if(v===ABSENT)return leaves;
    if(ref(v)){
      if(seen.has(v.id))error('cyclic output container unsupported',fn);seen.add(v.id);const o=ctx.heap.get(v.id);
      const add=map=>{for(const [key,value] of map){if(leaves.has(key))error(`duplicate output path ${key}`,fn);leaves.set(key,value);}};
      if(o.kind==='dictionary')for(const [key,e] of o.entries)add(flatten(e.value,path?path+'.'+key:key,and(present,e.present,ctx,fn),new Set(seen)));
      else o.items.forEach((x,i)=>add(flatten(x,`${path||'result'}[${i}]`,and(present,compare('<',i,o.length,ctx,fn),ctx,fn),new Set(seen))));return leaves;
    }
    leaves.set(path||'result',{value:v,present});return leaves;
  };
  for(const [path,leaf] of flatten(result,'')){outputs[path]=leaf.value;outputPresence[path]=leaf.present;}
  const outputFormulas={};for(const [path,value] of Object.entries(outputs))outputFormulas[path]=`=IF(${code(and(outputPresence[path],not(unavailable,ctx,fn),ctx,fn))},${code(value)},NA())`;
  if(cellBindings.outputs){const occupied=new Set(Object.keys(formulas).map(normalizedCell));for(const [path,address] of Object.entries(cellBindings.outputs)){if(!Object.hasOwn(outputs,path))error(`unknown output binding ${path}`,fn);if(!localCell(address))error(`invalid local output binding ${address}`,fn);const key=normalizedCell(address);if(occupied.has(key)||reservedInputs.has(key))error(`output/helper/input collision ${address}`,fn);occupied.add(key);formulas[address]=outputFormulas[path];sourceMap.push({cell:address,node:fn.id,source:fn.source,type:type(outputs[path]),output:path});}}
  const presenceFormulas=Object.fromEntries(Object.entries(outputPresence).map(([k,v])=>[k,code(v)]));
  const numericDescriptor=v=>choice(v)?{condition:code(v.condition),yes:numericDescriptor(v.yes),no:numericDescriptor(v.no)}:type(v)==='number'?numberType(v):null;
  const outputNumericTypes=Object.fromEntries(Object.entries(outputs).map(([path,v])=>[path,numericDescriptor(v)]).filter(([,tag])=>tag!==null));
  const descriptorPredicates=d=>d&&typeof d==='object'?[d.condition,...descriptorPredicates(d.yes),...descriptorPredicates(d.no)]:[];
  const numericPredicates=Object.values(outputNumericTypes).flatMap(descriptorPredicates);
  let emittedFormulas=formulas,emittedMap=sourceMap;
  if(optimize){
    // Reachability, not economic dead-code guesses: every output, its presence,
    // AND every validation/unavailability/diagnostic predicate is a root. Source
    // map predicates of retained cells stay live too. Strings are never scanned
    // as references. Compaction preserves operation order and fixed bindings.
    const tokens=/"(?:[^"]|"")*"|'[^']+'![A-Z]+[1-9][0-9]*/g;
    const references=formula=>[...formula.matchAll(tokens)].map(m=>m[0]).filter(x=>!x.startsWith('"')&&Object.hasOwn(formulas,x));
    const keep=new Set(),byCell=new Map(sourceMap.map(x=>[x.cell,x]));
    const pending=[...Object.values(outputFormulas),...Object.values(presenceFormulas),...numericPredicates,...diagnostics.map(x=>x.condition),...Object.values(cellBindings.outputs??{}).map(x=>'='+x)].flatMap(references);
    while(pending.length){const cell=pending.pop();if(keep.has(cell))continue;keep.add(cell);pending.push(...references(formulas[cell]),...references(byCell.get(cell)?.active??''));}
    // Pack single-use scalar DAG nodes without changing a single operator or
    // parenthesis. Guard/diagnostic references are materialized roots. This
    // reduces cells, NOT the number of arithmetic operations; no reassociation,
    // duplication, cross-guard motion or financial shortcut is performed.
    const uses=new Map(),formulaLocations=new Map(),addUse=(formula,location)=>{for(const dep of references(formula)){const locations=uses.get(dep)??[];locations.push(location);uses.set(dep,locations);}};
    // Redirect locations rather than rescanning all users of a shared guard
    // on each inline (quadratic for one guard with thousands of numeric users).
    const destination=location=>{const path=[];while(location.redirect){path.push(location);location=location.redirect;}for(const old of path)old.redirect=location;return location;};
    for(const cell of keep){const location={kind:'helper',key:cell};formulaLocations.set(cell,location);addUse(formulas[cell],location);}
    for(const [path,f] of Object.entries(outputFormulas))addUse(f,{kind:'output',key:path});
    for(const f of [...Object.values(presenceFormulas),...numericPredicates,...diagnostics.map(x=>x.condition),...sourceMap.filter(x=>keep.has(x.cell)).map(x=>x.active??'')])addUse(f,{kind:'root'});
    const destinations=new Set(Object.values(cellBindings.outputs??{}));
    const fits=formula=>{if(formula.length>4096)return false;let depth=0,maximum=0;for(const ch of formula.replace(/"(?:[^"]|"")*"/g,'')){if(ch==='(')maximum=Math.max(maximum,++depth);else if(ch===')')depth--;}return maximum<=48;};
    for(const entry of sourceMap){const cell=entry.cell,locations=uses.get(cell)??[];if(!keep.has(cell)||destinations.has(cell)||locations.length!==1)continue;
      const target=destination(locations[0]);if(target.kind==='root')continue;const container=target.kind==='helper'?formulas:outputFormulas;if(!Object.hasOwn(container,target.key))continue;
      // Excel MIN/MAX distinguish logical/text references from inline values.
      // Only numeric nodes may cross that reference-sensitive boundary.
      if(entry.type!=='number'&&/\b(?:MIN|MAX)\(/.test(container[target.key].replace(/"(?:[^"]|"")*"/g,'')))continue;
      const packed=container[target.key].replace(tokens,x=>x===cell?'('+formulas[cell].slice(1)+')':x);if(!fits(packed))continue;
      container[target.key]=packed;keep.delete(cell);packedHelpers++;
      const inherited=[{node:entry.node,source:entry.source,type:entry.type,active:entry.active},...entry.inlinedSources??[]];
      if(target.kind==='helper'){const parent=byCell.get(target.key);parent.inlinedSources=(parent.inlinedSources??[]).concat(inherited);}else{
        // The output has no physical destination until the author binds it.
        for(const origin of inherited)sourceMap.push({...origin,cell:null,output:target.key,inlined:true});
      }
      formulaLocations.get(cell).redirect=target;
    }
    let index=0;const remap=new Map(sourceMap.filter(x=>!x.output&&keep.has(x.cell)).map(x=>[x.cell,`'${sheet}'!${column}${firstRow+index++}`]));
    const rewrite=formula=>formula.replace(tokens,x=>remap.get(x)??x);
    emittedFormulas={};for(const [cell,formula] of Object.entries(formulas))if(keep.has(cell)||Object.values(cellBindings.outputs??{}).includes(cell))emittedFormulas[remap.get(cell)??cell]=rewrite(formula);
    for(const key of Object.keys(outputFormulas))outputFormulas[key]=rewrite(outputFormulas[key]);
    for(const key of Object.keys(presenceFormulas))presenceFormulas[key]=rewrite(presenceFormulas[key]);
    for(const d of diagnostics)d.condition=rewrite(d.condition);
    const rewriteDescriptor=d=>{if(!d||typeof d!=='object')return d;return {condition:rewrite(d.condition),yes:rewriteDescriptor(d.yes),no:rewriteDescriptor(d.no)};};
    for(const key of Object.keys(outputNumericTypes))outputNumericTypes[key]=rewriteDescriptor(outputNumericTypes[key]);
    emittedMap=sourceMap.filter(x=>keep.has(x.cell)||x.output).map(x=>({...x,cell:remap.get(x.cell)??x.cell,...(x.active?{active:rewrite(x.active)}:{}),...(x.inlinedSources?{inlinedSources:x.inlinedSources.map(origin=>({...origin,active:rewrite(origin.active??'TRUE')}))}:{})}));
  }
  const requiredFunctions=[...new Set(Object.values(emittedFormulas).concat(Object.values(outputFormulas)).flatMap(f=>[...f.replace(/"(?:[^"]|"")*"/g,'').matchAll(/\b([A-Z][A-Z0-9_]*)\(/g)].map(m=>m[1])))].sort();
  return {formulas:emittedFormulas,outputs:outputFormulas,outputPresence:presenceFormulas,outputNumericTypes,sourceMap:emittedMap,diagnostics,
    coverage:{functions:[...calls].sort(),nodes:[...coverage].filter(Number.isInteger).sort((a,b)=>a-b),loopProofs,outputPaths:Object.keys(outputs)},
    provenance:{canonicalSourceSha256:ir.canonicalSourceSha256,compilerVersion:ir.compilerVersion,backendVersion:EXCEL_BACKEND_VERSION,
      irSha256:ir.irSha256,bindingSha256:digest(JSON.stringify(cellBindings))},
    requirements:{formulaFunctions:requiredFunctions,unqualifiedNewPrimitives:requiredFunctions.includes('EXACT')?['EXACT']:[],engineQualification:'No engine execution by emitter; external capability evidence, whitelist integration and saved-file parity are separate'},
    statistics:{helperCells:Object.keys(emittedFormulas).length,allocatedHelpersBeforeLiveness:cellCount,dominatingExpressionReuses:cseHits,packedSingleUseHelpers:packedHelpers,prunedHelpers:cellCount-emittedMap.filter(x=>!x.output).length-packedHelpers,heapObjects:ctx.heap.size,symbolicOperations:operations,elapsedMilliseconds:performance.now()-start},
  };
}
