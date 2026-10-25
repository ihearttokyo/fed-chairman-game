import assert from 'node:assert/strict';
import fs from 'node:fs';
import { BooleanProof, composeOutputs, composeWholeOutputs, describeOutputs, CompositionError } from '../spreadsheet/model-compose.mjs';
import { compileModel } from '../spreadsheet/model-compiler.mjs';
import { emitExcel } from '../spreadsheet/model-excel.mjs';

const cell=n=>`'Policy'!A${n}`;
const types=Object.fromEntries(Array.from({length:12},(_,i)=>[cell(i+1),{type:'boolean'}]));
let groups=0;
const test=(name,run)=>{run();groups++;console.log('PASS '+name);};
const proof=(formulas={},options={})=>new BooleanProof({formulas,cellTypes:types},options);
const desc=(path,n,type='number',numericType='float',presenceCell=cell(1))=>({path,cell:cell(n),type,numericType,presenceCell});
const graph=descriptors=>({formulas:Object.fromEntries(descriptors.map(d=>[d.cell,`=IF(${d.presenceCell},0,NA())`])),descriptors,cellTypes:types});
const compose=(g,extra={})=>composeOutputs(g,{prefix:'state',adoption:cell(1),helperSheet:'Economy',helperColumn:'L',helperStartRow:10,...extra});
// Independent evaluator of the tiny admission dialect, including actual lazy
// errors and strict Boolean storage. Not the compiler/IR or a workbook engine.
class SourceGuardError extends Error {}
function guardValue(formulas,values,raw,seen=new Set()){
  let s=raw.replace(/^=/,'').trim();
  while(s.startsWith('(')&&s.endsWith(')')){let d=0,whole=true;for(let i=0;i<s.length;i++){if(s[i]==='(')d++;if(s[i]===')')d--;if(d===0&&i<s.length-1){whole=false;break;}}if(!whole)break;s=s.slice(1,-1).trim();}
  if(s==='TRUE')return true;if(s==='FALSE')return false;
  if(s==='NA()')throw new SourceGuardError('source error');if(/^-?[0-9]+(?:\.[0-9]+)?$/.test(s))return Number(s);
  if(/^"(?:[^"]|"")*"$/.test(s))return s.slice(1,-1).replaceAll('""','"');
  let level=0,quoted=false;for(let i=0;i<s.length;i++){if(s[i]==='"'){if(quoted&&s[i+1]==='"'){i++;continue;}quoted=!quoted;}if(quoted)continue;if(s[i]==='(')level++;if(s[i]===')')level--;if(level===0&&/[<>=]/.test(s[i])){const op=/^(?:<>|<=|>=|=|<|>)/.exec(s.slice(i))[0],a=guardValue(formulas,values,s.slice(0,i),seen),b=guardValue(formulas,values,s.slice(i+op.length),seen);return op==='='?a===b:op==='<>'?a!==b:op==='<'?a<b:op==='>'?a>b:op==='<='?a<=b:a>=b;}}let depthOp=0,multiply=-1;for(let i=0;i<s.length;i++){if(s[i]==='(')depthOp++;if(s[i]===')')depthOp--;if(depthOp===0&&s[i]==='*')multiply=i;}
  if(multiply>=0)return guardValue(formulas,values,s.slice(0,multiply),seen)*guardValue(formulas,values,s.slice(multiply+1),seen);
  if(Object.hasOwn(values,s))return values[s];
  if(Object.hasOwn(formulas,s)){if(seen.has(s))throw new SourceGuardError('cycle');return guardValue(formulas,values,formulas[s],new Set([...seen,s]));}
  const name=s.slice(0,s.indexOf('(')),args=[];let depth=0,start=name.length+1;
  for(let i=start;i<s.length;i++){if(s[i]==='(')depth++;if(s[i]===')'){if(depth===0){args.push(s.slice(start,i));break;}depth--;}if(s[i]===','&&depth===0){args.push(s.slice(start,i));start=i+1;}}
  const run=x=>guardValue(formulas,values,x,seen);
  if(name==='IF')return run(args[0])?run(args[1]):run(args[2]);
  if(name==='IFERROR'){try{return run(args[0]);}catch(e){if(!(e instanceof SourceGuardError))throw e;return run(args[1]);}}
  if(name==='ISLOGICAL'){try{return typeof run(args[0])==='boolean';}catch(e){if(!(e instanceof SourceGuardError))throw e;return false;}}
  if(name==='ISNUMBER'){try{return typeof run(args[0])==='number';}catch(e){if(!(e instanceof SourceGuardError))throw e;return false;}}
  if(name==='EXACT')return String(run(args[0]))===String(run(args[1]));
  if(name==='ISBLANK'){try{return run(args[0])===null;}catch(e){if(!(e instanceof SourceGuardError))throw e;return false;}}
  if(name==='INT')return Math.floor(run(args[0]));
  if(name==='ABS')return Math.abs(run(args[0]));
  if(name==='SIGN')return Math.sign(run(args[0]));
  if(name==='NOT')return !run(args[0]);throw Error('unhandled test guard '+s);
}

test('missing presence and availability cannot be captured by fresh helper cells',()=>{
  const missing="'Economy'!L2000",value="'Economy'!E20";
  for(const [presence,available]of [[missing,'TRUE'],['TRUE',missing],[missing,missing]])for(const helperColumn of ['L','M']){
    const g={formulas:{[value]:`=IF(${available},7,NA())`},cellTypes:{},descriptors:[{path:'state.x',cell:value,type:'number',numericType:'float',presence}]};
    const before=JSON.stringify(g);
    assert.throws(()=>composeOutputs(g,{prefix:'state',helperColumn}),e=>e instanceof CompositionError&&e.code==='UNBOUND_DEPENDENCY'&&e.details.cell===missing);
    assert.equal(JSON.stringify(g),before,'refusal must not rewrite or allocate into source data');
  }
});

test('all formula and metadata dependencies are admitted before allocation or pruning',()=>{
  const missing="'Economy'!L2000",value="'Economy'!E20",base=()=>({formulas:{[value]:'=IF(TRUE,7,NA())'},cellTypes:{},descriptors:[{path:'state.x',cell:value,type:'number',numericType:'float',presence:'TRUE'}]});
  for(const kind of ['adoption','numeric-choice','alternate-presence','unused-formula','inactive-arm','unselected-value']){
    const g=base(),options={prefix:'state',helperColumn:'!'};
    if(kind==='adoption')options.adoption=missing;
    if(kind==='numeric-choice')g.descriptors[0].numericType={condition:missing,yes:'float',no:'float'};
    if(kind==='alternate-presence')Object.assign(g.descriptors[0],{presenceCell:cell(1),presence:missing});
    if(kind==='alternate-presence')g.cellTypes[cell(1)]={type:'boolean'};
    if(kind==='unused-formula')g.formulas["'Economy'!G42"]=`=NOT(${missing})`;
    if(kind==='inactive-arm')g.formulas[value]=`=IF(TRUE,7,IF(${missing},8,NA()))`;
    if(kind==='unselected-value')g.descriptors.push({path:'other.x',cell:missing,type:'boolean',numericType:null,presence:'FALSE'});
    const before=JSON.stringify(g);Object.freeze(g.formulas);
    assert.throws(()=>composeOutputs(g,options),e=>e.code==='UNBOUND_DEPENDENCY'&&e.details.cell===missing,kind+' must refuse BEFORE invalid helper allocation');
    assert.equal(JSON.stringify(g),before);
  }
});

test('declared typed inputs and formula cells stay reserved, never captured',()=>{
  const upstream="'Economy'!L2000",value="'Economy'!E20";
  for(const declared of ['input','formula']){
    const g={formulas:{[value]:`=IF(${upstream},7,NA())`},cellTypes:{},descriptors:[{path:'state.x',cell:value,type:'number',numericType:'float',presence:upstream}]};
    if(declared==='input')g.cellTypes[upstream]={type:'boolean'};else g.formulas[upstream]='=TRUE';
    const before=JSON.stringify(g);assert.throws(()=>composeOutputs(g,{prefix:'state'}),e=>e.code==='CELL_COLLISION');
    const out=composeOutputs(g,{prefix:'state',helperColumn:'M'}),formulas={...g.formulas,...out.formulas};
    assert.equal(guardValue(formulas,declared==='input'?{[upstream]:true}:{},out.readyCell),true);
    if(declared==='input')for(const v of [false,null,'',3])assert.equal(guardValue(formulas,{[upstream]:v},out.readyCell),false,'an explicitly supplied blank/invalid presence is not healthy');
    assert.equal(JSON.stringify(g),before);
  }
});

test('quoted strings and escaped quotes do not invent source dependencies',()=>{
  const value="'Economy'!E20";
  for(const text of ['"\'Economy\'!L2000 Economy!$l$2000"','"quoted ""Economy!L2000"" text"']){
    const g={formulas:{[value]:`=IF(TRUE,${text},NA())`},cellTypes:{},descriptors:[{path:'state.x',cell:value,type:'string',numericType:null,presence:'TRUE'}]},before=JSON.stringify(g);
    const out=composeOutputs(g,{prefix:'state'});assert.ok(Object.hasOwn(out.formulas,"'Economy'!L2000"));
    assert.equal(guardValue(out.formulas,{},out.readyCell),true);assert.equal(JSON.stringify(g),before);
  }
});

test('case, quote and absolute-reference aliases share one canonical upstream cell',()=>{
  const canonical="'Economy'!L2000",value="'Economy'!E20",aliases=[canonical,'Economy!$L$2000',"'eCoNoMy'!$l$2000",'economy!l2000'];
  for(const alias of aliases){
    const g={formulas:{[value]:`=IF(${alias},7,NA())`},cellTypes:{},descriptors:[{path:'state.x',cell:value,type:'number',numericType:'float',presence:alias}]},before=JSON.stringify(g);
    assert.throws(()=>composeOutputs(g,{prefix:'state'}),e=>e.code==='UNBOUND_DEPENDENCY'&&e.details.cell===canonical);
    g.cellTypes[alias]={type:'boolean'};assert.throws(()=>composeOutputs(g,{prefix:'state'}),e=>e.code==='CELL_COLLISION');
    const p=new BooleanProof(g);assert.equal(p.implies([alias],canonical).proved,true);
    const out=composeOutputs(g,{prefix:'state',helperColumn:'M'});assert.equal(out.value.x.present.cell,canonical);assert.ok(!Object.hasOwn(out.formulas,canonical));
    delete g.cellTypes[alias];assert.equal(JSON.stringify(g),before);
  }
  for(const section of ['formulas','cellTypes']){
    const a=section==='formulas'?'=TRUE':{type:'boolean'},b=section==='formulas'?'=FALSE':{type:'boolean'};
    assert.throws(()=>new BooleanProof({formulas:{},cellTypes:{},[section]:{[canonical]:a,'economy!$l$2000':b}}),e=>e.code==='CELL_ALIAS');
  }
});

test('unproved reference syntax and unknown functions refuse rather than assume blanks',()=>{
  for(const predicate of ['L2000',"'Economy'!L2000:L2001",'INDIRECT("Economy!L2000")','OFFSET(1,0,0)','UNKNOWN(TRUE)',"'[book]Economy'!L2000",'"unterminated']){
    const g={formulas:{[cell(10)]:`=IF(${predicate},7,NA())`},cellTypes:{},descriptors:[desc('state.x',10)]},before=JSON.stringify(g);
    assert.throws(()=>composeOutputs(g,{prefix:'state'}),CompositionError,predicate);assert.equal(JSON.stringify(g),before);
  }
});

test('Boolean-only implication, aliases, lazy IF and independent opaque atoms',()=>{
  const p=proof({[cell(3)]:`=IF(${cell(1)},${cell(2)},FALSE)`,[cell(4)]:`=IF(${cell(1)},TRUE,${cell(2)})`});
  assert.equal(p.implies([cell(3)],cell(1)).proved,true);
  assert.equal(p.implies([cell(3)],cell(2)).proved,true);
  assert.equal(p.implies([cell(1)],cell(4)).proved,true);
  assert.equal(p.implies([cell(4)],cell(1)).proved,false);
  assert.equal(p.implies(['1=2'],'1<>2').proved,false,'no numeric/comparison inference');
  assert.equal(p.unreachable(['IFERROR(NA(),TRUE)']).proved,false);
  assert.equal(p.implies(['IF(TRUE,TRUE,NA())'],'TRUE').proved,true);
});

test('real reachable equal-valued int/float alternatives decline in both modes',()=>{
  for(const optimize of [true,false]){
    const ir=compileModel('func run(flag: bool) -> Dictionary:\n\treturn {"v":2 if flag else 2.0}\n',{entrypoints:['run']});
    const p=emitExcel(ir,{entrypoint:'run',optimize,arguments:{flag:{cell:cell(1),type:'boolean'}},outputs:{v:cell(10)}});
    const descriptors=describeOutputs(p);
    assert.throws(()=>composeOutputs({...p,descriptors,cellTypes:types},{prefix:'',adoption:'TRUE'}),e=>e instanceof CompositionError&&e.code==='CONDITIONAL_TYPE');
    for(const flag of [true,false])assert.equal(new BooleanProof({...p,cellTypes:types}).unreachable([{expression:cell(1),value:flag}]).proved,false);
  }
});

test('presence can refine nested numeric choices, never from the number value',()=>{
  const d=desc('state.n',10,'dictionary',{condition:cell(2),yes:{condition:cell(1),yes:'int',no:'float'},no:'int'},cell(3));
  const g=graph([d]);g.formulas[cell(3)]=`=IF(${cell(1)},${cell(4)},FALSE)`;
  const before=JSON.stringify(g),out=compose(g,{adoption:'TRUE'});
  assert.equal(out.value.n.value.numericType,'int');assert.equal(out.value.n.value.type,'number');
  assert.equal(JSON.stringify(g),before,'input metadata/formulas unchanged');
});

test('unknown conditions, exhausted work and lazy error-sensitive expressions fail closed',()=>{
  const d=desc('state.n',10,'dictionary',{condition:'IFERROR(NA(),TRUE)',yes:'int',no:'float'});
  assert.throws(()=>compose(graph([d])),e=>e.code==='CONDITIONAL_TYPE');
  assert.equal(proof({}, {maxSteps:1}).implies([cell(1)],cell(2)).proved,false);
  assert.equal(proof({[cell(3)]:`=${cell(4)}`,[cell(4)]:`=${cell(3)}`}).implies([cell(3)],'FALSE').proved,false);
  assert.equal(proof().implies(['AND(NA(),FALSE)'],'FALSE').proved,false,'eager error constructs stay opaque');
});

test('structural scalar/array overlap removed only under proven adoption mask',()=>{
  const scalar=desc('state.a',10,'number','float',cell(2)),element=desc('state.a[0]',11,'number','float',cell(3));
  const g=graph([scalar,element]);g.formulas[cell(2)]=`=NOT(${cell(1)})`;g.formulas[cell(3)]=`=${cell(1)}`;
  const out=compose(g);assert.equal(out.omitted.length,1);assert.equal(out.omitted[0].path,'state.a');assert.equal(out.value.a.value.length,1);
  assert.throws(()=>compose(g,{adoption:'TRUE'}),e=>e.code==='PATH_OVERLAP');
  assert.throws(()=>compose(graph([scalar,element])),e=>e.code==='PATH_OVERLAP');
});

test('absence, availability and nullable/category provenance are not filled with zero',()=>{
  const d=desc('state.n',10,'number','float',cell(2)),g=graph([d]);g.formulas[d.cell]=`=IF(${cell(3)},IF(${cell(2)},7,NA()),NA())`;
  const out=compose(g);assert.equal(out.value.n.value.cell,d.cell);assert.equal(out.value.n.present.cell,d.presenceCell);
  assert.ok(out.constraints.some(c=>c.kind==='source-availability'));
  assert.throws(()=>compose(graph([desc('state.nil',10,'null',null)])),e=>e.code==='UNREPRESENTED_TYPE');
  assert.throws(()=>compose(graph([desc('state.choice',10,'dictionary',{condition:cell(2),yes:'int',no:null})])),e=>e.code==='CONDITIONAL_TYPE');
});

test('malicious, ambiguous, sparse and duplicate paths refuse',()=>{
  for(const path of ['state.__proto__.x','state.constructor','state.a[01]','state.a[-1]','state..x','state.a[9007199254740993]'])assert.throws(()=>compose(graph([desc(path,10)])),CompositionError);
  assert.throws(()=>compose(graph([desc('state.a[1]',10)])),e=>e.code==='SPARSE_ARRAY');
  assert.throws(()=>compose(graph([desc('state.a',10),desc('state.a',11)])),e=>e.code==='DUPLICATE_PATH');
  assert.throws(()=>compose(graph([desc('state.a[0]',10),desc('state.a.b',11)])),e=>e.code==='MIXED_CONTAINER');
  assert.throws(()=>compose(graph([desc('state.a',10)]),{prefix:'stat'}),e=>e.code==='NO_OUTPUTS');
});

test('closed metadata rejects accessors, cycles and mutable ambiguous cell aliases',()=>{
  let callbacks=0;const hostile={};Object.defineProperty(hostile,'formulas',{enumerable:true,get(){callbacks++;return {};}});
  assert.throws(()=>new BooleanProof(hostile),CompositionError);assert.equal(callbacks,0);
  const d=desc('state.n',10,'dictionary',{});d.numericType.condition=cell(1);d.numericType.yes=d.numericType;d.numericType.no='int';
  assert.throws(()=>compose(graph([d])),CompositionError);
  assert.throws(()=>proof({[cell(3)]:'=TRUE','Policy!$A$3':'=FALSE'}),e=>e.code==='CELL_ALIAS');
  for(const field of ['extra','numericType']){const x=desc('other.n',10);x[field]={toJSON(){callbacks++;return 'int';}};assert.throws(()=>compose(graph([x])),CompositionError);}
  const hidden=desc('other.n',10);Object.defineProperty(hidden,'toJSON',{value(){callbacks++;return {};}});assert.throws(()=>compose(graph([hidden])),CompositionError);
  assert.throws(()=>compose(graph([desc('state.n',10)]),{helperSheet:{toString(){callbacks++;return 'Economy';}}}),CompositionError);
  assert.equal(callbacks,0);
});

test('no formula/value/error/presence rewriting; fresh guards do not collide',()=>{
  const g=graph([desc('state.a[0]',10),desc('state.a[1]',11,'number','float',cell(2))]),before=JSON.stringify(g),out=compose(g);
  assert.equal(JSON.stringify(g),before);assert.equal(out.value.a.value[0].cell,cell(10));
  assert.ok(Object.values(out.formulas).every(f=>f.startsWith('=IF(')||f.startsWith('=')));
  assert.throws(()=>compose(g,{helperSheet:'Policy',helperColumn:'A',helperStartRow:10}),e=>e.code==='CELL_COLLISION');
});

test('complete adoption discharges wrappers only behind every original guard',()=>{
  const g=graph([desc('state.a[0]',10),desc('state.a[1]',11,'number','float',cell(2))]),out=compose(g);
  assert.equal(out.adopted.predicate,out.readyCell);assert.equal(out.adopted.value.a[0].cell,cell(10));
  const p=new BooleanProof({formulas:{...g.formulas,...out.formulas},cellTypes:types});
  for(const c of out.adopted.obligations)for(const guard of [c.presenceCell,...c.predicates])assert.equal(p.implies([out.readyCell],guard).proved,true);
  assert.equal(p.unreachable([out.readyCell,{expression:cell(2),value:false}]).proved,true);
});

test('live but unavailable fields cannot disappear into an otherwise healthy shape',()=>{
  const g=graph([desc('state.a',10),desc('state.b',11,'boolean',null)]);g.formulas[cell(11)]='=IF(FALSE,TRUE,NA())';
  const out=compose(g);assert.equal(out.omitted.length,0);assert.ok(out.value.b);
  const p=new BooleanProof({formulas:{...g.formulas,...out.formulas},cellTypes:types});assert.equal(p.unreachable([out.readyCell]).proved,true);
  g.descriptors[1]=desc('state.b',11);assert.throws(()=>compose(g),e=>e.code==='CONDITIONAL_TYPE'&&e.details.alternatives.length===0);
});

test('errored or cyclic presence is not absence; inactive lazy errors stay inactive',()=>{
  for(const expr of ['IF(NA(),FALSE,FALSE)',`IF(${cell(2)},FALSE,FALSE)`]){
    const g=graph([desc('state.a',10),desc('state.b',11,'boolean',null,cell(3))]);g.formulas[cell(3)]='='+expr;
    const out=compose(g),formulas={...g.formulas,...out.formulas};
    assert.equal(guardValue(formulas,{[cell(1)]:true,[cell(2)]:null},out.readyCell),expr.includes('NA()')?false:true);
    assert.ok(out.adopted.presenceAdmission.length===2,'even omitted paths retain type/error admission');
    if(out.omitted.length)assert.ok(out.omitted.every(d=>out.adopted.presenceAdmission.includes(d.requiredPresenceAdmission)));
  }
  const g=graph([desc('state.a',10),desc('state.b',11,'boolean',null,cell(3))]);g.formulas[cell(3)]=`=IF(${cell(3)},FALSE,TRUE)`;
  const out=compose(g);assert.equal(guardValue({...g.formulas,...out.formulas},{[cell(1)]:true},out.readyCell),false);
});

test('presence admission rejects numeric/text/blank category coercion',()=>{
  const g=graph([desc('state.a',10,'boolean',null,cell(2))]),out=compose(g);
  for(const p of [true,false,3,0,'TRUE','',null])assert.equal(guardValue({...g.formulas,...out.formulas},{[cell(1)]:true,[cell(2)]:p},out.readyCell),p===true);
  for(const a of [true,false,3,0,'TRUE','',null])assert.equal(guardValue({...g.formulas,...out.formulas},{[cell(1)]:a,[cell(2)]:true},out.readyCell),a===true);
});

test('empty containers are an explicit metadata coverage gap, not inferred contents',()=>{
  const ir=compileModel('func run() -> Dictionary:\n\treturn {"a":[],"b":1.0}\n',{entrypoints:['run']});
  const p=emitExcel(ir,{entrypoint:'run',outputs:{b:cell(10)}}),descriptors=describeOutputs(p);
  const out=composeOutputs({...p,descriptors,cellTypes:types},{prefix:''});
  assert.equal(out.adopted.projectionOnly,true);assert.match(out.qualification,/empty containers are unencoded/);assert.ok(!Object.hasOwn(out.value,'a'));
});

test('bounded proof soundness against independent three-valued lazy evaluation',()=>{
  const E=Symbol('error'),names=[cell(1),cell(2),cell(3)],leaves=[...names,'TRUE','FALSE','NA()'];let seed=583;
  const rand=n=>{seed=(seed*1664525+1013904223)>>>0;return seed%n;};
  const tree=depth=>depth===0?leaves[rand(leaves.length)]:rand(3)===0?['NOT',tree(depth-1)]:['IF',tree(depth-1),tree(depth-1),tree(depth-1)];
  const text=t=>Array.isArray(t)?`${t[0]}(${t.slice(1).map(text).join(',')})`:t;
  const run=(t,env)=>{if(!Array.isArray(t))return t==='TRUE'?true:t==='FALSE'?false:t==='NA()'?E:env[t];const c=run(t[1],env);return c===E?E:t[0]==='NOT'?!c:run(c?t[2]:t[3],env);};
  let assertions=0,proved=0;
  for(let i=0;i<80;i++){
    const a=tree(2),b=tree(2),p=proof(),result=p.implies([text(a)],text(b));
    if(!result.proved)continue;proved++;
    for(const x of [false,true,E])for(const y of [false,true,E])for(const z of [false,true,E]){const env={[names[0]]:x,[names[1]]:y,[names[2]]:z};assert.ok(!(run(a,env)===true&&run(b,env)===false),'unsound Boolean proof');assertions++;}
  }
  assert.ok(proved>0);console.log('INDEPENDENT PROOF CHECKS',assertions);
});

// Optional bounded regression: resident source-composed metadata, not a workbook
// or a native execution. No expected numeric output is given to the compositor.
if(process.env.FED_COMPOSE_REAL_PLAN)test('both current579 quarter descriptors and all structural alternatives',()=>{
  const plan=JSON.parse(fs.readFileSync(process.env.FED_COMPOSE_REAL_PLAN,'utf8'));
  const stage=plan.stages.find(s=>s.name==='step'),cellTypes=Object.fromEntries(plan.inputCells.map(x=>[x.cell,{type:x.type,numericType:x.numericType}]));
  const before=JSON.stringify(plan),adoption=stage.descriptors.find(d=>d.path==='ok').cell;
  for(const path of ['state.quarter_index','trace.quarter_index']){
    const d=stage.descriptors.find(d=>d.path===path),out=composeOutputs({formulas:plan.formulas,descriptors:[d],cellTypes},{prefix:path.split('.')[0],adoption,helperSheet:'Economy',helperColumn:'M',helperStartRow:100});
    assert.equal(out.value.quarter_index.value.numericType,'int');
  }
  const out=composeOutputs({formulas:plan.formulas,descriptors:stage.descriptors,cellTypes},{prefix:'state',adoption,helperSheet:'Economy',helperColumn:'M',helperStartRow:100});
  assert.equal(out.value.quarter_index.value.numericType,'int');
  // The sixth history capacity slot has a numeric length predicate. It is NOT
  // discarded from this old graph using a sampled native length or arithmetic.
  assert.deepEqual(out.constraints.filter(c=>c.kind==='complete-source-array-only').map(c=>c.length).sort((a,b)=>a-b),[4,6,120,120]);
  assert.equal(out.omitted.filter(d=>['state.treasury_cohorts_pct_initial_gdp','state.sterilized_treasury_cohorts_pct_initial_gdp','state.bill_cohorts_pct_initial_gdp'].includes(d.path)).length,3);
  assert.equal(JSON.stringify(plan),before);console.log('REAL PROOF',JSON.stringify(out.statistics));
});


const wholeFixture609=(source,args={},extra={})=>{
  const ir=compileModel(source,{entrypoints:['run']}),base={entrypoint:'run',arguments:args,includeOutputStructure:true};
  const discovery=emitExcel(ir,base),outputs=Object.fromEntries(Object.keys(discovery.outputs).map((path,i)=>[path,`'Policy'!F${100+i}`]));
  const program=emitExcel(ir,{...base,outputs}),descriptors=describeOutputs(program),cellTypes=Object.fromEntries(Object.values(args).filter(v=>v&&v.cell).map(({cell,type,numericType})=>[cell,{type,...(numericType?{numericType}:{})}]));
  const graph={formulas:program.formulas,descriptors,cellTypes,structure:program.outputStructure};
  const composed=composeWholeOutputs(graph,{helperColumn:'O',...extra});return {graph,program,composed,formulas:{...graph.formulas,...composed.formulas}};
};
test('whole609 empty Dictionary descendants and empty Array elements survive source composition',()=>{
  const f=wholeFixture609('func run() -> Dictionary:\n\treturn {"a":1,"empty":{},"items":[1,{}],"none":null,"empty_array":[]}\n');
  assert.deepEqual(f.composed.value.empty,{});assert.deepEqual(f.composed.value.items[1],{});assert.equal(f.composed.value.items.length,2);assert.equal(f.composed.value.none,null);assert.deepEqual(f.composed.value.empty_array,[]);
  assert.equal(guardValue(f.formulas,{},f.composed.readyCell),true);
});
test('whole609 known source key order survives and unknown source order refuses',()=>{
  const ordered=wholeFixture609('func run() -> Dictionary:\n\treturn {"b":2,"a":1}\n');assert.deepEqual(Object.keys(ordered.composed.value),['b','a']);
  assert.throws(()=>wholeFixture609('func run(flag: bool) -> Dictionary:\n\tvar d := {}\n\tif flag:\n\t\td["a"]=1\n\t\td["b"]=2\n\telse:\n\t\td["b"]=2\n\t\td["a"]=1\n\treturn d\n',{flag:{cell:cell(1),type:'boolean'}}),e=>e.code==='ORDER');
  assert.throws(()=>wholeFixture609('func run() -> Dictionary:\n\treturn {"2":"first","1":"second"}\n'),e=>e.code==='PATH','numeric-looking scalar paths remain outside the admitted input protocol');
});
test('whole609 complete live length gates shrinking arrays instead of dropping or padding objects',()=>{
  const f=wholeFixture609('func run(flag: bool) -> Array:\n\tvar a := [1,{}]\n\tif flag:\n\t\ta.pop_back()\n\treturn a\n',{flag:{cell:cell(1),type:'boolean'}});
  assert.equal(f.composed.value.length,2);assert.deepEqual(f.composed.value[1],{});
  assert.equal(guardValue(f.formulas,{[cell(1)]:false},f.composed.readyCell),true);assert.equal(guardValue(f.formulas,{[cell(1)]:true},f.composed.readyCell),false);
});
test('whole609 false errored and nonBoolean adoption never yield an admitted successor',()=>{
  const f=wholeFixture609('func run(gate: bool) -> Dictionary:\n\treturn {"v":1}\n',{gate:{cell:cell(1),type:'boolean'}}, {adoption:cell(1)});
  for(const value of [false,3,null,''])assert.equal(guardValue(f.formulas,{[cell(1)]:value},f.composed.readyCell),false);
});
test('whole609 missing structural dependencies refuse before helper allocation even outside prefix',()=>{
  const f=wholeFixture609('func run() -> Dictionary:\n\treturn {"state":{"x":1},"other":{}}\n');
  const g=structuredClone(f.graph),other=g.structure.root.entries.find(e=>e.key==='other');assert.ok(other);other.node.presence="'Economy'!O2000";
  assert.throws(()=>composeWholeOutputs(g,{prefix:'state'}),e=>e.code==='UNBOUND_DEPENDENCY'&&e.details.cell==="'Economy'!O2000");
});
test('whole609 preserves upstream byte identity and follows explicit output relay availability',()=>{
  const f=wholeFixture609('func run() -> Dictionary:\n\treturn {"v":1,"empty":{}}\n'),g=structuredClone(f.graph),d=g.descriptors.find(d=>d.path==='v');
  const original=d.cell;d.cell="'Policy'!D20";g.formulas[d.cell]='='+original;const before=JSON.stringify(g),out=composeWholeOutputs(g);
  assert.equal(JSON.stringify(g),before);assert.equal(out.value.v.cell,"'Policy'!D20");assert.deepEqual(out.value.empty,{});assert.equal(guardValue({...g.formulas,...out.formulas},{},out.readyCell),true);
  assert.throws(()=>composeWholeOutputs(g,{helperColumn:'F',helperSheet:'Policy',helperStartRow:100}),e=>e.code==='CELL_COLLISION');
});
test('whole609 rejects metadata callbacks and contradictory source child paths',()=>{
  const f=wholeFixture609('func run() -> Dictionary:\n\treturn {"v":1}\n');let invoked=0;
  for(const target of ['root','structure','descriptor']){
    const g=structuredClone(f.graph),object=target==='root'?g.structure.root:target==='structure'?g.structure:g.descriptors[0];object.toJSON=()=>{invoked++;return {};};
    assert.throws(()=>composeWholeOutputs(g),e=>e.code==='STRUCTURE'||e.code==='METADATA');
  }
  assert.equal(invoked,0);const g=structuredClone(f.graph);g.structure.root.entries[0].node.segments=['wrong'];assert.throws(()=>composeWholeOutputs(g),e=>e.code==='STRUCTURE');
});
test('whole609 absent errored and nonBoolean source presence keep the whole view unavailable',()=>{
  const f=wholeFixture609('func run() -> Dictionary:\n\treturn {"v":1}\n');
  for(const source of ['=FALSE','=NA()','=3']){
    const g=structuredClone(f.graph);g.structure.root.presence=cell(1);g.formulas[cell(1)]=source;const out=composeWholeOutputs(g);
    assert.equal(guardValue({...g.formulas,...out.formulas},{},out.readyCell),false);
  }
  const g=structuredClone(f.graph);g.structure.availability='NA()';const out=composeWholeOutputs(g);assert.equal(guardValue({...g.formulas,...out.formulas},{},out.readyCell),false);
});

test('whole609 explicit Dictionary view selects a source shape without inventing its presence',()=>{
  const source='func run(flag: bool) -> Dictionary:\n\tif flag:\n\t\treturn {"v":1,"empty":{}}\n\treturn {"error":"no"}\n';
  const f=wholeFixture609(source,{flag:{cell:cell(1),type:'boolean'}},{dictionaryKeys:['empty','v']});
  assert.deepEqual(Object.keys(f.composed.value),['v','empty']);assert.deepEqual(f.composed.value.empty,{});
  assert.equal(guardValue(f.formulas,{[cell(1)]:true},f.composed.readyCell),true);assert.equal(guardValue(f.formulas,{[cell(1)]:false},f.composed.readyCell),false);
  assert.throws(()=>composeWholeOutputs(f.graph,{dictionaryKeys:['invented']}),e=>e.code==='NO_OUTPUTS');
});


test('whole609 composed source containers retain downstream has size and empty-element observations',()=>{
  const f=wholeFixture609('func run() -> Dictionary:\n\treturn {"a":1,"empty":{},"items":[1,{}]}\n');
  const consumer=compileModel('func run(d: Dictionary) -> Array:\n\treturn [d.has("empty"),d.empty.size(),d.items.size(),d.items[1].size()]\n',{entrypoints:['run']});
  const p=emitExcel(consumer,{entrypoint:'run',helperColumn:'P',arguments:{d:f.composed.value}}),formulas={...f.formulas,...p.formulas};
  for(const [path,want]of Object.entries({'result[0]':true,'result[1]':0,'result[2]':2,'result[3]':0}))assert.equal(guardValue(formulas,{},p.outputs[path]),want,path);
});

test('whole609 contradictory structural versus descriptor scalar tags refuse',()=>{
  for(const [source,mutate]of [
    ['func run() -> Dictionary:\n\treturn {"v":1.5}\n',g=>{g.structure.root.entries[0].node.numericType='int';}],
    ['func run() -> Dictionary:\n\treturn {"v":1}\n',g=>{g.descriptors[0].numericType='float';}],
    ['func run() -> Dictionary:\n\treturn {"v":"text"}\n',g=>{g.structure.root.entries[0].node.type='boolean';}],
    ['func run() -> Dictionary:\n\treturn {"v":1.5}\n',g=>{Object.assign(g.structure.root.entries[0].node,{type:'null',numericType:null});}],
  ]){const g=structuredClone(wholeFixture609(source).graph);mutate(g);assert.throws(()=>composeWholeOutputs(g),e=>e.code==='TYPE_MISMATCH');}
});
test('whole609 rejects nested segment kind and helper-option callbacks before coercion',()=>{
  const f=wholeFixture609('func run() -> Dictionary:\n\treturn {"v":1}\n');let invoked=0;
  const callback={toJSON(){invoked++;return 'v';},toString(){invoked++;return 'Economy';}};
  for(const mutate of [g=>{g.structure.root.entries[0].node.segments=[callback];},g=>{g.structure.root.kind=callback;},g=>{g.descriptors[0].type=callback;},g=>{g.descriptors[0].presence=callback;}]){
    const g=structuredClone(f.graph);mutate(g);assert.throws(()=>composeWholeOutputs(g),e=>e instanceof CompositionError);
  }
  for(const key of ['helperSheet','helperColumn'])assert.throws(()=>composeWholeOutputs(f.graph,{[key]:callback}),e=>e.code==='CELL');
  assert.equal(invoked,0,'refusal must precede callback execution');
});
test('leaf609 availability admission is strictly Boolean including numeric text blank and errors',()=>{
  const v="'Economy'!E20",g={formulas:{[v]:`=IF(${cell(1)},7,NA())`},cellTypes:{[cell(1)]:{type:'boolean'}},descriptors:[{path:'state.x',cell:v,type:'number',numericType:'float',presence:'TRUE'}]};
  const out=composeOutputs(g,{prefix:'state'}),formulas={...g.formulas,...out.formulas};
  for(const value of [true,false,0,3,'true','',null]){const ready=guardValue(formulas,{[cell(1)]:value},out.readyCell);assert.equal(typeof ready,'boolean');assert.equal(ready,value===true);}
  const errored=structuredClone(g);delete errored.cellTypes[cell(1)];errored.formulas[cell(1)]='=NA()';const bad=composeOutputs(errored,{prefix:'state'});assert.equal(guardValue({...errored.formulas,...bad.formulas},{},bad.readyCell),false);
});

test('whole609 legitimate NIL retains strict source availability and cannot bypass failed guards',()=>{
  const f=wholeFixture609('func run() -> Dictionary:\n\treturn {"v":null}\n');assert.equal(f.composed.value.v,null);assert.equal(guardValue(f.formulas,{},f.composed.readyCell),true);
  for(const guard of ['FALSE','NA()','3']){
    const g=structuredClone(f.graph),d=g.descriptors.find(x=>x.path==='v');g.formulas[d.cell]=`=IF(${guard},NA(),NA())`;const out=composeWholeOutputs(g);
    assert.equal(out.value.v,null);assert.equal(guardValue({...g.formulas,...out.formulas},{},out.readyCell),false);
  }
});
console.log(`PASS ${groups} compositor groups; actual engine/workbook/native/research calls 0`);
