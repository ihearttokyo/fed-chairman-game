import assert from 'node:assert/strict';
import fs from 'node:fs';
import { compileModel, evaluateModel, roundAway, modelNumber } from '../spreadsheet/model-compiler.mjs';

let checks = 0;
const test = (name, run) => { if(process.env.FED_MODEL_TEST_FILTER&&!name.includes(process.env.FED_MODEL_TEST_FILTER))return;run(); checks++; console.log(`PASS ${name}`); };
const unit = body => `extends RefCounted\nfunc run(x: float) -> Variant:\n${body}\n`;
const compile = text => compileModel(text, { entrypoints: ['run'] });
// BEGIN FED597 additions: native4.7.2 receiver -> RHS -> index -> read/write.
// Source: /private/tmp/fed596-language-oracle/project/oracle.gd
// result.json SHA256: 15ec4ef21c886c9cb40a1524e113f9d9ad6f814930a1e1a48c45abb31df2e9bf
const nativeSource597="extends SceneTree\nfunc _receiver(a: Array, events: Array) -> Array:\n\tevents.append(\"receiver\")\n\treturn a\nfunc _index(events: Array, index: int) -> int:\n\tevents.append(\"index\")\n\treturn index\nfunc _rhs(a: Array, events: Array) -> Variant:\n\tevents.append(\"rhs\")\n\treturn a.pop_back()\nfunc assignment(index: int, compound: bool) -> Dictionary:\n\tvar a := [1, 7]\n\tvar events: Array = []\n\tif compound:\n\t\t_receiver(a, events)[_index(events, index)] += _rhs(a, events)\n\telse:\n\t\t_receiver(a, events)[_index(events, index)] = _rhs(a, events)\n\treturn {\"array\": a, \"events\": events}\nfunc order(flag: bool) -> Array:\n\tvar d := {}\n\tif flag:\n\t\td[\"2\"] = \"two\"\n\t\td[\"1\"] = \"one\"\n\telse:\n\t\td[\"1\"] = \"one\"\n\t\td[\"2\"] = \"two\"\n\tvar out: Array = []\n\tfor k in d:\n\t\tout.append(k)\n\treturn out\nfunc run(i: int, c: bool) -> Dictionary:\n\treturn assignment(i,c)\n";
const nativeCases597=[{"index":0,"compound":false,"expected":{"array":[7],"events":["receiver","rhs","index"]}},{"index":0,"compound":true,"expected":{"array":[8],"events":["receiver","rhs","index"]}},{"index":-1,"compound":false,"expected":{"array":[7],"events":["receiver","rhs","index"]}},{"index":-1,"compound":true,"expected":{"array":[8],"events":["receiver","rhs","index"]}}];
const receiverRhsIndex597=op=>'func receiver(holder: Dictionary,e: Array) -> Array:\n\te.append("receiver")\n\treturn holder.a\nfunc rhs(a: Array,holder: Dictionary,e: Array) -> int:\n\te.append("rhs")\n\ta[0] = 99\n\tholder.a = [1000]\n\treturn a[0]\nfunc index(a: Array,e: Array) -> int:\n\te.append("index")\n\ta[0] = 100.0\n\treturn 0\nfunc run() -> Array:\n\tvar a := [7]\n\tvar holder := {"a":a}\n\tvar e := []\n\treceiver(holder,e)[index(a,e)] '+op+' rhs(a,holder,e)\n\treturn [a[0],typeof(a[0]),holder.a[0],e]\n';
const emptyGrowth597=(op,index,erase=false)=>'func receiver(a: Array,e: Array) -> Array:\n\te.append("receiver")\n\treturn a\nfunc rhs(a: Array,e: Array) -> int:\n\te.append("rhs")\n\ta.append(5)\n\treturn 3\nfunc index(a: Array,e: Array) -> int:\n\te.append("index")\n\t'+(erase?'a.resize(0)':'a.append(9)')+'\n\treturn '+index+'\nfunc run() -> Array:\n\tvar a := []\n\tvar e := []\n\treceiver(a,e)[index(a,e)] '+op+' rhs(a,e)\n\treturn [a,e]\n';
const member597=(key,indexed)=>'func receiver(d: Dictionary,e: Array) -> Dictionary:\n\te.append("receiver")\n\treturn d\nfunc rhs(d: Dictionary,e: Array) -> int:\n\te.append("rhs")\n\td["'+key+'"] = 9.0\n\treturn 2\nfunc index(d: Dictionary,e: Array) -> String:\n\te.append("index")\n\td["'+key+'"] = 12.0\n\treturn "'+key+'"\nfunc run() -> Array:\n\tvar d := {}\n\tvar e := []\n\treceiver(d,e)'+(indexed?'[index(d,e)]':'.'+key)+' /= rhs(d,e)\n\treturn [d["'+key+'"],typeof(d["'+key+'"]),e]\n';
test('FED597 actual native assignment cases and event order match stored oracle',()=>{
  const ir=compile(nativeSource597);for(const row of nativeCases597)assert.deepEqual(evaluateModel(ir,'run',[row.index,row.compound]),row.expected);
});
test('FED597 receiver captured once RHS value captured then index mutation precedes target read',()=>{
  for(const op of ['=','+='])assert.deepEqual(evaluateModel(compile(receiverRhsIndex597(op)),'run'),[op==='='?99:199,op==='='?2:3,1000,['receiver','rhs','index']]);
});
test('FED597 initially empty Array grows before live index and index may invalidate bounds',()=>{
  for(const op of ['=','+='])for(const i of ['0','-1'])assert.deepEqual(evaluateModel(compile(emptyGrowth597(op,i)),'run'),[i==='0'?[op==='='?3:8,9]:[5,op==='='?3:12],['receiver','rhs','index']]);
  for(const op of ['=','+='])assert.throws(()=>evaluateModel(compile(emptyGrowth597(op,'0',true)),'run'),e=>e.name==='ModelCompileError'&&/array index out of bounds/.test(e.message));
});
test('FED597 member and Dictionary index compound targets use post-RHS and post-index values',()=>{
  for(const key of ['value','numericType','__proto__','constructor','toString'])for(const indexed of [true,false])assert.deepEqual(evaluateModel(compile(member597(key,indexed)),'run'),[indexed?6:4.5,3,indexed?['receiver','rhs','index']:['receiver','rhs']]);
});
test('FED597 typed name assignments retain source type conversion and RHS events',()=>{
  const source='func rhs(e: Array) -> float:\n\te.append("rhs")\n\treturn 2.0\nfunc run() -> Array:\n\tvar e := []\n\tvar n: int = 7\n\tn /= rhs(e)\n\tvar f: float = 7.0\n\tf /= rhs(e)\n\treturn [n,typeof(n),f,typeof(f),e]\n';assert.deepEqual(evaluateModel(compile(source),'run'),[3,2,3.5,3,['rhs','rhs']]);
});
test('FED597 lazy assignments skip receiver RHS and index while invalid receiver guards remain',()=>{
  const source=nativeSource597+'func guarded(flag: bool,i: int,c: bool) -> Dictionary:\n\tvar a := [1,7]\n\tvar e := []\n\tif flag:\n\t\tif c:\n\t\t\t_receiver(a,e)[_index(e,i)] += _rhs(a,e)\n\t\telse:\n\t\t\t_receiver(a,e)[_index(e,i)] = _rhs(a,e)\n\treturn {"array":a,"events":e}\n';
  const ir=compileModel(source,{entrypoints:['guarded']});for(const row of nativeCases597){assert.deepEqual(evaluateModel(ir,'guarded',[true,row.index,row.compound]),row.expected);assert.deepEqual(evaluateModel(ir,'guarded',[false,row.index,row.compound]),{array:[1,7],events:[]});}
  for(const numeric of ['7','7.0'])assert.throws(()=>evaluateModel(compile(`func run() -> Variant:\n\tvar v := ${numeric}\n\tv["value"] = 1\n\treturn v\n`),'run'),e=>e.name==='ModelCompileError'&&/receiver/.test(e.message));
});
// END FED597 additions.

// BEGIN FED596 additions; all prior120 groups remain byte-identical below.
const bounds596=e=>e.name==='ModelCompileError'&&/array index out of bounds/.test(e.message);
const unknownNegative596=e=>e.name==='ModelCompileError'&&/negative.*length|length.*negative/.test(e.message);
test('FED596 live write emptying RHS cannot resurrect simple compound or aliased Array slots',()=>{
  for(const op of ['=','+='])for(const receiver of ['a','alias','holder.a'])for(const rhs of ['a','alias','holder.a']){
    const s=`func run() -> Array:\n\tvar a := [7]\n\tvar alias := a\n\tvar holder := {"a":a}\n\t${receiver}[0] ${op} ${rhs}.pop_back()\n\treturn [a.size(),a[0]]\n`;assert.throws(()=>evaluateModel(compile(s),'run'),bounds596);
  }
});
test('FED596 native post-RHS Array values preserve valid writes and NIL arithmetic refusal',()=>{
  for(const [op,shrink,grow,regrow]of [['=',11,5,3],['+=',18,12,null]]){
    assert.deepEqual(evaluateModel(compile(`func run() -> Array:\n\tvar a := [7,11]\n\ta[0] ${op} a.pop_back()\n\treturn [a.size(),a[0]]\n`),'run'),[1,shrink]);
    const g=`func grow(a: Array) -> int:\n\ta.append(9)\n\treturn 5\nfunc run() -> Array:\n\tvar a := [7]\n\tvar alias := a\n\ta[0] ${op} grow(alias)\n\treturn [a.size(),a[0],a[1]]\n`;assert.deepEqual(evaluateModel(compile(g),'run'),[2,grow,9]);
    const q=`func regrow(a: Array) -> int:\n\ta.pop_back()\n\ta.resize(1)\n\treturn 3\nfunc run() -> Array:\n\tvar a := [7]\n\ta[0] ${op} regrow(a)\n\treturn [a.size(),a[0],typeof(a[0])]\n`;for(const program of [q,q.replace('a[0] '+op,'a[-1] '+op)]){if(op==='=')assert.deepEqual(evaluateModel(compile(program),'run'),[1,regrow,2]);else assert.throws(()=>evaluateModel(compile(program),'run'),/Boolean\/non-numeric/);}
  }
});
test('FED596 native RHS precedes index and compound target read',()=>{
  const source='func receiver(a: Array,c: Array) -> Array:\n\tc[0] += 1\n\treturn a\nfunc index(c: Array) -> int:\n\tc[1] += 1\n\treturn 0\nfunc rhs(a: Array,c: Array) -> int:\n\tc[2] += 1\n\ta[0] = 99\n\treturn 1\nfunc run() -> Array:\n\tvar a := [7]\n\tvar c := [0,0,0]\n\treceiver(a,c)[index(c)] += rhs(a,c)\n\treturn [a[0],c[0],c[1],c[2]]\n';assert.deepEqual(evaluateModel(compile(source),'run'),[100,1,1,1]);
  const indexMutation='func index(a: Array,c: Array) -> int:\n\tc[0] += 1\n\ta.pop_back()\n\treturn -1\nfunc run() -> Array:\n\tvar a := [7,11]\n\tvar c := [0]\n\ta[index(a,c)] = 3\n\treturn [a.size(),a[0],c[0]]\n';assert.deepEqual(evaluateModel(compile(indexMutation),'run'),[1,3,1]);
});
test('FED596 native live negative normalization supports final valid bounds',()=>{
  for(const op of ['=','+=']){
    const shrink=`func run() -> Array:\n\tvar a := [7,11]\n\tvar alias := a\n\ta[-1] ${op} alias.pop_back()\n\treturn a\n`;assert.deepEqual(evaluateModel(compile(shrink),'run'),[op==='='?11:18]);
    const grow=`func grow(a: Array) -> int:\n\ta.append(9)\n\treturn 5\nfunc run() -> Array:\n\tvar a := [7,11]\n\ta[-1] ${op} grow(a)\n\treturn a\n`;assert.deepEqual(evaluateModel(compile(grow),'run'),[7,11,op==='='?5:14]);
    assert.throws(()=>evaluateModel(compile(`func run() -> Array:\n\tvar a := [7]\n\ta[-1] ${op} a.pop_back()\n\treturn a\n`),'run'),bounds596);
    assert.deepEqual(evaluateModel(compile(`func run() -> Array:\n\tvar a := [7,11]\n\ta[-1] ${op} 3\n\treturn a\n`),'run'),[7,op==='='?3:14]);
  }
  assert.deepEqual(evaluateModel(compile('func grow(a: Array) -> int:\n\ta.append(9)\n\treturn 5\nfunc run() -> Array:\n\tvar a := [7]\n\ta[1] = grow(a)\n\treturn a\n'),'run'),[7,5]);
});
test('FED596 inactive Array RHS mutations stay inert and live guards are branch-specific',()=>{
  for(const op of ['=','+=']){
    const bad=compile(`func run(flag: bool) -> Array:\n\tvar a := [7]\n\tif flag:\n\t\ta[0] ${op} a.pop_back()\n\treturn [a.size(),a[0]]\n`);assert.deepEqual(evaluateModel(bad,'run',[false]),[1,7]);assert.throws(()=>evaluateModel(bad,'run',[true]),bounds596);
    const neg=compile(`func run(flag: bool) -> Array:\n\tvar a := [7,11]\n\ta[-1] ${op} (a.pop_back() if flag else 3)\n\treturn a\n`);assert.deepEqual(evaluateModel(neg,'run',[false]),[7,op==='='?3:14]);assert.deepEqual(evaluateModel(neg,'run',[true]),[op==='='?11:18]);
  }
  for(const index of ['0','-1'])for(const op of ['=','+=']){
    const c=compile(`func run(flag: bool) -> Array:\n\tvar a := [7]\n\tvar b := [11]\n\tvar target = a if flag else b\n\ttarget[${index}] ${op} a.pop_back()\n\treturn [a.size(),b.size(),b[0]]\n`);assert.deepEqual(evaluateModel(c,'run',[false]),[0,1,op==='='?7:18]);assert.throws(()=>evaluateModel(c,'run',[true]),bounds596);
  }
  const initial=compile('func grow(a: Array) -> int:\n\ta.append(9)\n\treturn 5\nfunc run(flag: bool) -> Array:\n\tvar a := [7]\n\tif flag:\n\t\ta[1] = grow(a)\n\treturn [a.size(),a[0]]\n');assert.deepEqual(evaluateModel(initial,'run',[false]),[1,7]);assert.deepEqual(evaluateModel(initial,'run',[true]),[2,7]);
});
test('FED596 Dictionary creation and overwrites retain chronological RHS effects and compound reads',()=>{
  const source='func create(d: Dictionary) -> int:\n\td.numericType = 5\n\treturn 7\nfunc overwrite(d: Dictionary) -> int:\n\td.value = 99\n\treturn 1\nfunc run() -> Array:\n\tvar d := {}\n\td.value = create(d)\n\td.value += overwrite(d)\n\treturn [d.keys(),d.value,d.numericType]\n';assert.deepEqual(evaluateModel(compile(source),'run'),[['numericType','value'],100,5]);
});
// END FED596 additions.

// BEGIN FED594 additions; all prior108 groups remain byte-identical below.
const receiver594=e=>e.name==='ModelCompileError'&&/receiver/.test(e.message);
test('FED594 numeric receiver direct and input member index reads refuse before lookup',()=>{
  for(const literal of ['7','7.0'])for(const access of ['.value','.numericType','["value"]','["numericType"]']){
    assert.throws(()=>evaluateModel(compile(`func run() -> Variant:\n\treturn (${literal})${access}\n`),'run'),receiver594);
    const ir=compile(`func run(v: Variant) -> Variant:\n\treturn v${access}\n`);assert.throws(()=>evaluateModel(ir,'run',[modelNumber(7,literal==='7'?'int':'float')]),receiver594);
  }
  for(const literal of ['7','7.0'])assert.throws(()=>evaluateModel(compile(`func run() -> String:\n\treturn str((${literal}).numericType)\n`),'run'),receiver594);
});
test('FED594 numeric receiver lazy and conditional reads preserve inactive paths and valid Dictionary arms',()=>{
  for(const literal of ['7','7.0'])for(const access of ['.value','.numericType','["value"]','["numericType"]']){
    const ir=compile(`func run(flag: bool) -> Variant:\n\tvar v := ${literal}\n\treturn v${access} if flag else "safe"\n`);assert.equal(evaluateModel(ir,'run',[false]),'safe');assert.throws(()=>evaluateModel(ir,'run',[true]),receiver594);
    const key=access.includes('numericType')?'numericType':'value',mixed=compile(`func run(flag: bool) -> Variant:\n\tvar v = ${literal} if flag else {"${key}":"visible"}\n\treturn v${access}\n`);assert.equal(evaluateModel(mixed,'run',[false]),'visible');assert.throws(()=>evaluateModel(mixed,'run',[true]),receiver594);
  }
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\tif false:\n\t\tvar hidden = (7).value\n\treturn [false and (7).value>0,true or (7.0).value>0,(7).numericType if false else "safe"]\n'),'run'),[false,true,'safe']);
});
test('FED594 numeric receiver assignment and compound locations reject explicitly and stay lazy',()=>{
  for(const literal of ['7','7.0'])for(const access of ['.value','.numericType','["value"]','["numericType"]'])for(const op of ['=','+=']){
    const ir=compile(`func run(flag: bool) -> String:\n\tvar v := ${literal}\n\tif flag:\n\t\tv${access} ${op} 1\n\treturn "safe"\n`);assert.equal(evaluateModel(ir,'run',[false]),'safe');assert.throws(()=>evaluateModel(ir,'run',[true]),receiver594);
  }
  for(const literal of ['7','7.0'])for(const access of ['.value','.numericType','["value"]','["numericType"]'])for(const op of ['=','+=']){
    const key=access.includes('numericType')?'numericType':'value',ir=compile(`func run(flag: bool) -> Variant:\n\tvar v = ${literal} if flag else {"${key}":5}\n\tv${access} ${op} 1\n\treturn v${access}\n`);assert.equal(evaluateModel(ir,'run',[false]),op==='='?1:6);assert.throws(()=>evaluateModel(ir,'run',[true]),receiver594);
  }
  assert.throws(()=>evaluateModel(compile('func run() -> String:\n\tvar v := 7\n\tv.value = str([1])\n\treturn "safe"\n'),'run'),receiver594,'receiver location is admitted before evaluating assignment RHS');
});
test('FED594 legitimate Dictionary field names remain writable readable and own-key safe',()=>{
  const s='func run() -> Array:\n\tvar d := {"value":7,"numericType":"int","__proto__":2,"constructor":"ctor","toString":"text"}\n\tvar alias := d\n\talias.value += 1\n\td["numericType"] = "float"\n\talias.__proto__ += 3\n\td["constructor"] = "new"\n\td.toString = "kept"\n\treturn [d.value,d["value"],d.numericType,d["numericType"],d.__proto__,d["__proto__"],d.constructor,d.toString,d.get("value"),d.has("numericType"),d.size()]\n';
  assert.deepEqual(evaluateModel(compile(s),'run'),[8,8,'float','float',5,5,'new','kept',8,true,5]);
  const input=JSON.parse('{"value":7,"numericType":"external","__proto__":"own","constructor":"ctor","toString":"text"}'),before=JSON.stringify(input);
  assert.deepEqual(evaluateModel(compile('func run(d: Dictionary) -> Array:\n\td.value = 9\n\treturn [d.value,d.numericType,d.__proto__,d.constructor,d.toString]\n'),'run',[input]),[9,'external','own','ctor','text']);assert.equal(JSON.stringify(input),before);
});
test('FED594 Array access remains numeric integral negative inbounds and preserves method dispatch',()=>{
  const s='func run(i: int) -> Array:\n\tvar a := [2,4,null]\n\tvar alias := a\n\talias[-3] += 1\n\ta[1] = 8\n\treturn [a[0],a[-2],a.get(-3),a.get(1),a[i],a[0.0],a.get(-2.0),a.size(),a.has(8),a[-1]==null,"7.5".is_valid_float()]\n';
  for(const [i,value]of [[0,3],[1,8],[-3,3],[-2,8]])assert.deepEqual(evaluateModel(compile(s),'run',[i]),[3,8,3,8,value,3,8,3,true,true,true]);
  for(const index of ['"0"','"length"','true','null','0.5','3','-4','INF','NAN']){
    for(const use of [`return a[${index}]`,`a[${index}] = 9\n\treturn 1`,`a[${index}] += 1\n\treturn 1`,`return a.get(${index})`])assert.throws(()=>evaluateModel(compile('func run() -> Variant:\n\tvar a := [1,2,3]\n\t'+use+'\n'),'run'),/array index/);
  }
});
test('FED594 unsupported member index receiver domains refuse rather than JS box primitives',()=>{
  for(const value of ['true','null','"abc"','[1,2]'])assert.throws(()=>evaluateModel(compile(`func run() -> Variant:\n\treturn (${value}).length\n`),'run'),receiver594);
  for(const value of ['true','null','"abc"'])assert.throws(()=>evaluateModel(compile(`func run() -> Variant:\n\treturn (${value})["0"]\n`),'run'),receiver594);
  for(const value of ['true','null','"abc"','[1,2]'])assert.throws(()=>evaluateModel(compile(`func run() -> int:\n\tvar v = ${value}\n\tv.length = 1\n\treturn 9\n`),'run'),receiver594);

  for(const index of ['0','true','null'])assert.throws(()=>evaluateModel(compile(`func run() -> Variant:\n\treturn {"0":"zero"}[${index}]\n`),'run'),/dictionary key must be String/);
  for(const value of ['7','7.0'])assert.throws(()=>evaluateModel(compile(`func run() -> Variant:\n\treturn (${value}).get(0)\n`),'run'),/invalid receiver/);
});
// END FED594 additions.

// BEGIN FED593 additions; all prior93 groups remain byte-identical below.
import {builtinValue as builtin593} from '../spreadsheet/model-compiler.mjs';
test('FED593 str simple source literals retain exact numeric provenance and actual String NIL',()=>{
  const s='func run() -> Array:\n\treturn [str(null),str(true),str(false),str(7),str(7.0),str(-7),str(-7.0),str(0),str(0.0),str("MiXeD"),str("7.00"),typeof(str(1)),typeof(str(null)),str(7)==str(7.0),str(1e0),str(1000000.0)]\n';
  assert.deepEqual(evaluateModel(compile(s),'run'),['<null>','true','false','7','7.0','-7','-7.0','0','0.0','MiXeD','7.00',4,4,false,'1.0','1000000.0']);
  assert.deepEqual(evaluateModel(compile('const S = str(7.0)\nfunc run() -> Array:\n\treturn [S,str(float(7)),str(int(7.0)),str(7/2),str(7.0+0.0)]\n'),'run'),['7.0','7.0','7','3','7.0']);
});
test('FED593 str numeric formatting and external unknown subtype refuse rather than guess',()=>{
  const ir=compile('func run(v: Variant) -> String:\n\treturn str(v)\n');
  for(const [v,expected]of [[modelNumber(7,'int'),'7'],[modelNumber(7,'float'),'7.0'],[modelNumber(-9007199254740991,'int'),'-9007199254740991'],[modelNumber(9007199254740991,'int'),'9007199254740991']])assert.equal(evaluateModel(ir,'run',[v]),expected);
  for(const v of [7,modelNumber(7,'unknown'),modelNumber(7.5,'float'),modelNumber(-0,'float'),modelNumber(1000001,'float'),modelNumber(NaN,'float'),modelNumber(Infinity,'float')])assert.throws(()=>evaluateModel(ir,'run',[v]),/str.*(?:provenance|format|domain)/);
  assert.equal(evaluateModel(ir,'run',[7],{numericInputs:'float'}),'7.0');
  for(const v of ['0.1','7.5','-0.0','1000001.0','INF','NAN'])assert.throws(()=>evaluateModel(compile(`func run() -> String:\n\treturn str(${v})\n`),'run'),/str.*(?:provenance|format|domain)/);
  assert.throws(()=>builtin593('str',[7]),/str.*provenance/);
});
test('FED593 str containers consistently refuse instead of host JS stringify',()=>{
  for(const value of ['[10,20,30]','[]','{}','{"v":7}','{"v":[null]}'])assert.throws(()=>evaluateModel(compile(`func run() -> String:\n\treturn str(${value})\n`),'run'),/str.*(?:container|domain)/);
  for(const value of [[10,20,30],[],{},null]){if(value===null)assert.equal(builtin593('str',[value]),'<null>');else assert.throws(()=>builtin593('str',[value]),/str.*(?:container|domain)/);}
});
test('FED593 str live Boolean String NIL and metadata fields preserve content case and category',()=>{
  const ir=compile('func run(v: Variant) -> String:\n\treturn str(v)\n');for(const [v,expected]of [[true,'true'],[false,'false'],[null,'<null>'],['MiXeD','MiXeD'],['TRUE','TRUE'],['',''],['7.0','7.0']])assert.equal(evaluateModel(ir,'run',[v]),expected);
  const row={key:'policy_rate',source:'https://example.invalid/Source',unit:'Percent',description:'CaSe and "quotes"',id:'scenario_id'};
  assert.deepEqual(evaluateModel(compile('func run(row: Dictionary) -> Array:\n\treturn [str(row.key),str(row.source),str(row.unit),str(row.description),str(row.id)]\n'),'run',[row]),Object.values(row));
});
test('FED593 str inactive unsupported branches stay lazy and active failures never become strings',()=>{
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\treturn [str([1]) if false else "safe",false and str({})=="x",true or str(0.1)=="x",str(null) if true else str([1])]\n'),'run'),['safe',false,true,'<null>']);
  const ir=compile('func run(flag: bool) -> String:\n\treturn str([1]) if flag else "safe"\n');assert.equal(evaluateModel(ir,'run',[false]),'safe');assert.throws(()=>evaluateModel(ir,'run',[true]),/str.*container/);
  const error=compile('func run(flag: bool) -> String:\n\treturn str(log(-1.0)) if flag else "safe"\n');assert.equal(evaluateModel(error,'run',[false]),'safe');assert.throws(()=>evaluateModel(error,'run',[true]),/str.*format/);
});
test('FED593 str owned NIL and defaults differ from absent field and direct NIL',()=>{
  const ir=compile('func run() -> Array:\n\tvar d := {"v":null}\n\tvar a := [null]\n\ta.resize(2)\n\treturn [str(d.v),str(d.get("missing")),str(d.get("missing","default")),str(a[0]),str(a.get(-1)),typeof(str(d.v))]\n');assert.deepEqual(evaluateModel(ir,'run'),['<null>','<null>','default','<null>','<null>',4]);
  assert.throws(()=>evaluateModel(compile('func run() -> String:\n\treturn str({}.missing)\n'),'run'),/missing/);
});
test('FED593 str runtime choices keep equal-valued int float and source categories separate',()=>{
  const source='func run(flag: bool,v: Variant) -> Array:\n\treturn [str(7 if flag else 7.0),str(null if flag else v),str(flag),str("ABC" if flag else "def"),str(v==null)]\n';
  for(const flag of [true,false])assert.deepEqual(evaluateModel(compile(source),'run',[flag,'MiXeD']),flag?['7','<null>','true','ABC','false']:['7.0','MiXeD','false','def','false']);
  const absent=compile('func run(flag: bool) -> String:\n\tvar d := {} if flag else {"v":null}\n\treturn str(d.v)\n');assert.equal(evaluateModel(absent,'run',[false]),'<null>');assert.throws(()=>evaluateModel(absent,'run',[true]),/missing/);
});
// END FED593 additions.

// BEGIN FED591 additions; all prior84 groups remain byte-identical below.
import {modelConstants as constants591,dictionaryEntries as entries591,binaryValue as binary591} from '../spreadsheet/model-compiler.mjs';
test('FED591 branch-order actual interpreter histories stay ordered through for copy merge',()=>{
  const pre='func run(flag: bool) -> Array:\n\tvar d := {}\n\tif flag:\n\t\td["2"] = "two"\n\t\td["1"] = "one"\n\telse:\n\t\td["1"] = "one"\n\t\td["2"] = "two"\n';
  for(const middle of ['', '\tvar c := d.duplicate(true)\n\td = c\n','\tvar c := {}\n\tc.merge(d.duplicate(true),true)\n\td = c\n']){const ir=compile(pre+middle+'\tvar out := []\n\tfor k in d:\n\t\tout.append(k)\n\treturn out\n');for(const flag of [true,false])assert.deepEqual(evaluateModel(ir,'run',[flag]),flag?['2','1']:['1','2']);}
});
test('FED591 branch-order reinsertion after conditional absence has actual creation order',()=>{
  for(const insertion of ['d["2"] = "two"','d.merge({"2":"two"},true)']){const s='func run(flag: bool) -> Array:\n\tvar d := {}\n\tif flag:\n\t\td["2"] = "two"\n\td["1"] = "one"\n\t'+insertion+'\n\treturn d.keys()\n';for(const flag of [true,false])assert.deepEqual(evaluateModel(compile(s),'run',[flag]),flag?['2','1']:['1','2']);}
});
test('FED591 external-reinput forgets stale order while constants stay immutable and ordered',()=>{
  const make=compile('func run() -> Dictionary:\n\treturn {"a":"A","b":"B","nested":{"a":"A","b":"B"}}\n'),keys=compile('func run(d: Dictionary) -> Array:\n\treturn d.keys()\n'),nested=compile('func run(d: Dictionary) -> Array:\n\treturn d.nested.keys()\n');
  for(const preserveNumericTypes of [false,true]){const d=evaluateModel(make,'run',[],{preserveNumericTypes});delete d.a;d.a='A';delete d.nested.a;d.nested.a='A';assert.deepEqual(evaluateModel(keys,'run',[d]),['b','nested','a']);assert.deepEqual(evaluateModel(nested,'run',[d]),['b','a']);assert.deepEqual(entries591(d).entries.map(([k])=>k),['b','nested','a']);d.c='C';assert.deepEqual(evaluateModel(keys,'run',[d]),['b','nested','a','c']);}
  const numeric=evaluateModel(compile('func run() -> Dictionary:\n\treturn {"2":"two","1":"one"}\n'),'run');assert.throws(()=>evaluateModel(keys,'run',[numeric]),/external.*order|order.*external/);assert.equal(entries591(numeric).orderProved,false);
  for(const preserveNumericTypes of [false,true]){const c=constants591(compile('const D = {"2":"two","1":"one"}\nfunc run() -> Array:\n\treturn D.keys()\n'),{preserveNumericTypes});assert.equal(Object.isFrozen(c),true);assert.equal(Object.isFrozen(c.D),true);assert.throws(()=>{delete c.D['2'];},TypeError);assert.deepEqual(entries591(c.D).entries.map(([k])=>k),['2','1']);}
});
test('FED591 logical-resize regrowth creates NIL after conditional shrink pop and aliases',()=>{
  for(const mutation of ['alias.pop_back()','alias.resize(1)']){const s='func run(flag: bool) -> Array:\n\tvar a := [1,7]\n\tvar alias := a\n\tif flag:\n\t\t'+mutation+'\n\ta.resize(2)\n\treturn [typeof(a[1]),a[1]==null,9 if a[1]==null else a[1]]\n';for(const flag of [true,false])assert.deepEqual(evaluateModel(compile(s),'run',[flag]),flag?[0,true,9]:[2,false,7]);}
  const s='func run(p: bool,q: bool) -> Array:\n\tvar a := [1,7]\n\tif p:\n\t\ta.pop_back()\n\tif q:\n\t\ta.resize(2)\n\treturn [a.size(),typeof(a[-1]),a[-1]==null]\n';for(const p of [true,false])for(const q of [true,false])assert.deepEqual(evaluateModel(compile(s),'run',[p,q]),[p&&!q?1:2,p&&q?0:2,p&&q]);
  const empty=compile('func run(flag: bool) -> Array:\n\tvar a := []\n\tif flag:\n\t\ta.append(7)\n\ta.pop_back()\n\ta.resize(1)\n\treturn [typeof(a[0]),a[0]==null]\n');assert.deepEqual(evaluateModel(empty,'run',[true]),[0,true]);assert.throws(()=>evaluateModel(empty,'run',[false]),/pop.*empty/);
});
test('FED591 membership-receiver rejects numeric internal fields before property inspection',()=>{
  for(const receiver of ['7','7.0','true','null'])for(const op of ['in','not in'])for(const key of ['value','numericType'])assert.throws(()=>evaluateModel(compile(`func run() -> bool:\n\treturn "${key}" ${op} ${receiver}\n`),'run'),/membership.*receiver|receiver.*membership/);
  for(const op of ['in','not in'])assert.throws(()=>binary591(op,'value',modelNumber(7,'int')),/membership.*receiver|receiver.*membership/);
  assert.throws(()=>evaluateModel(compile('func run() -> bool:\n\treturn 1 in "1"\n'),'run'),/String.*membership|membership.*String/);
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\treturn ["Tag" in "Taggy","tag" in "Taggy","X" not in "Taggy","__proto__" in {"__proto__":7},7 in [7.0],7 not in [7.0]]\n'),'run'),[true,false,true,true,false,true]);
  assert.equal(evaluateModel(compile('func run() -> int:\n\tif false:\n\t\tvar unused = "value" in 7\n\treturn 9\n'),'run'),9);
});
// END FED591 additions.

// BEGIN FED590 additions; prior70 groups below remain byte-identical.
test('FED590 4369440164 shared Variant-sensitive has in not-in',()=>{
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\treturn [7 in [7.0],7 not in [7.0],7 in [7],7.0 in [7.0],true in [1],null in [null],"Tag" in ["tag"],7==7.0]\n'),'run'),[false,true,true,true,false,true,false,true]);
  const s='func run(v: Variant) -> Array:\n\treturn [[7].has(v),v in [7],v not in [7]]\n';
  for(const [v,hand]of [[modelNumber(7,'int'),[true,true,false]],[modelNumber(7,'float'),[false,false,true]],[true,[false,false,true]],[null,[false,false,true]]])assert.deepEqual(evaluateModel(compile(s),'run',[v]),hand);
  assert.throws(()=>evaluateModel(compile(s),'run',[7]),/membership.*provenance|provenance.*membership/);
  assert.throws(()=>evaluateModel(compile('func run() -> bool:\n\treturn [1] in [[1]]\n'),'run'),/membership.*scalar|scalar.*membership/);
});
test('FED590 4369440168 source Dictionary insertion order survives mutation copy merge and for',()=>{
  const s='func run() -> Array:\n\tvar d := {"2":"a","1":"b","01":"c","4294967294":"d","4294967295":"e","__proto__":"p","constructor":"k","toString":"t"}\n\tvar alias := d\n\talias["1"] = "B"\n\td.merge({"2":"wrong","new":"n","01":"wrong"},false)\n\tvar shallow := d.duplicate(false)\n\tvar deep := d.duplicate(true)\n\tdeep["1"] = "deep"\n\tshallow["tail"] = "s"\n\tvar visits := []\n\tfor k in d:\n\t\tvisits.append(k)\n\treturn [d.keys(),d.values(),visits,shallow.keys(),deep.keys(),d["1"],deep["1"]]\n';
  const keys=['2','1','01','4294967294','4294967295','__proto__','constructor','toString','new'];
  assert.deepEqual(evaluateModel(compile(s),'run'),[keys,['a','B','c','d','e','p','k','t','n'],keys,keys.concat('tail'),keys,'B','deep']);
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\tvar d := {"2":2,"1":1}\n\td.merge({"2":20,"01":3,"1":10},true)\n\treturn [d.keys(),d.values()]\n'),'run'),[['2','1','01'],[20,10,3]]);
});
test('FED590 4369440169 present null indices get resize and defaults never become zero',()=>{
  const s='func run() -> Array:\n\tvar a := [null,7,null]\n\ta.resize(4)\n\tvar d := {"v":null}\n\treturn [typeof(a[0]),a[0]==null,typeof(a[-1]),a.get(-1)==null,a.get(-3)==7,typeof(a.get(0)),a.get(0)==null,typeof(d.get("v",9)),d.get("v",9)==null,d.get("missing",9),d.get("missing",null)==null]\n';
  assert.deepEqual(evaluateModel(compile(s),'run'),[0,true,0,true,true,0,true,0,true,9,true]);
  const dyn=compile('func run(i: int) -> Array:\n\tvar a := [null,7]\n\tvar v = a[i]\n\tvar g = a.get(i)\n\treturn [typeof(v),v==null,typeof(g),g==null,9 if v==null else v]\n');
  for(const i of [0,-2,1,-1])assert.deepEqual(evaluateModel(dyn,'run',[i]),[i===0||i===-2?0:2,i===0||i===-2,i===0||i===-2?0:2,i===0||i===-2,i===0||i===-2?9:7]);
  assert.throws(()=>evaluateModel(compile('func run() -> Variant:\n\treturn [null].get(3)\n'),'run'),/index|bounds/);
  assert.throws(()=>evaluateModel(compile('func run() -> Variant:\n\treturn [null].get(0,9)\n'),'run'),/get.*argument|argument.*get/);
});
test('FED590 4369440171 empty live containers use source truthiness in every Boolean context',()=>{
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\treturn [not [],not {},1 if [] else 2,1 if {} else 2,[] and log(-1.0)>0,[1] or log(-1.0)>0,{} or false,{"v":null} and true]\n'),'run'),[true,true,2,2,false,true,false,true]);
  const s='func run(flag: bool) -> Array:\n\tvar a := []\n\tvar alias := a\n\tvar before = not a\n\tif flag:\n\t\talias.append(null)\n\tvar middle = not a\n\tif flag:\n\t\talias.pop_back()\n\tvar d := {}\n\tvar other := d\n\tvar empty = not d\n\tother.merge({"v":null},true)\n\treturn [before,middle,not a,empty,not d,1 if d else 2,a and true,a or false]\n';
  for(const flag of [true,false])assert.deepEqual(evaluateModel(compile(s),'run',[flag]),[true,!flag,true,true,false,1,false,false]);
});
test('FED590 source constants preserve numeric-looking key order across module boundaries',()=>{
  assert.deepEqual(evaluateModel(compile('const D = {"2":"first","1":"second","01":"third"}\nfunc run() -> Array:\n\treturn [D.keys(),D.values()]\n'),'run'),[['2','1','01'],['first','second','third']]);
});
test('FED590 external numeric-looking Dictionary order refuses observation without lost-order guesses',()=>{
  const d=JSON.parse('{"2":"first","1":"second","01":"third"}');
  for(const action of ['return d.keys()','return d.values()','var out := []\n\tfor k in d:\n\t\tout.append(k)\n\treturn out','var c := d.duplicate(true)\n\treturn c.keys()'])assert.throws(()=>evaluateModel(compile('func run(d: Dictionary) -> Variant:\n\t'+action+'\n'),'run',[d]),/external.*order|order.*external/);
  assert.deepEqual(evaluateModel(compile('func run(d: Dictionary) -> Array:\n\treturn [d["2"],d["1"],d.has("01"),not d]\n'),'run',[d]),['first','second',true,false]);
});
test('FED590 source null is false but an owned null entry makes a Dictionary nonempty',()=>{
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\tvar a := [null]\n\tvar d := {"v":null}\n\treturn [not a,not a[0],not d,not d.v,d.get("v",true)==null,d.get("missing",true)]\n'),'run'),[false,true,false,true,true,true]);
});
// END FED590 additions.

test('FED586 own String keys survive merge copy unboxing input and output boundaries',()=>{
  const merge=compile('func run() -> Array:\n\tvar d := {}\n\td.merge({"__proto__":7},true)\n\treturn [d.size(),d.has("__proto__"),d.get("__proto__",9)]\n');
  assert.deepEqual(evaluateModel(merge,'run'),[1,true,7]);
  const root=compile('func run() -> Dictionary:\n\treturn {"__proto__":"kept","constructor":"ctor","toString":"text","safe":"yes"}\n'),hand=JSON.parse('{"__proto__":"kept","constructor":"ctor","toString":"text","safe":"yes"}');
  for(const preserveNumericTypes of [false,true]){const got=evaluateModel(root,'run',[],{preserveNumericTypes});assert.deepEqual(got,hand);assert.equal(Object.getPrototypeOf(got),Object.prototype);for(const key of Object.keys(hand))assert.equal(Object.hasOwn(got,key),true);assert.deepEqual(JSON.parse(JSON.stringify(got)),hand);}
  const copy=compile('func run() -> Array:\n\tvar a := [1]\n\tvar d := {"__proto__":a,"constructor":a,"toString":a}\n\tvar deep := d.duplicate(true)\n\tvar shallow := d.duplicate(false)\n\ta[0] = 9\n\tdeep["__proto__"][0] = 7\n\treturn [deep["constructor"][0],deep["toString"][0],shallow["__proto__"][0],a[0],deep["__proto__"][0]/2,typeof(deep["__proto__"][0]),deep]\n');
  assert.deepEqual(evaluateModel(copy,'run'),[7,7,9,9,3,2,JSON.parse('{"__proto__":[7],"constructor":[7],"toString":[7]}')]);
  const input=compile('func run(d: Dictionary) -> Dictionary:\n\tvar out := {}\n\tout.merge(d.duplicate(true),true)\n\treturn out\n');assert.deepEqual(evaluateModel(input,'run',[hand]),hand);
  const overwrite=compile('func run() -> Array:\n\tvar d := {"__proto__":1,"constructor":2,"toString":3}\n\td.merge({"__proto__":7,"constructor":8,"toString":9},false)\n\tvar old := d.duplicate(true)\n\td.merge({"__proto__":7,"constructor":8,"toString":9},true)\n\treturn [old,d]\n');assert.deepEqual(evaluateModel(overwrite,'run'),[JSON.parse('{"__proto__":1,"constructor":2,"toString":3}'),JSON.parse('{"__proto__":7,"constructor":8,"toString":9}')]);
  assert.equal(Object.hasOwn(Object.prototype,'safe'),false,'no host prototype mutation');
  const symbols=compile('const __proto__: int = 5\nfunc constructor(__proto__: int) -> int:\n\tvar toString := __proto__\n\tif toString > 0:\n\t\ttoString += 2\n\treturn toString\nfunc run() -> Array:\n\tvar __proto__ := constructor(__proto__)\n\treturn [__proto__,typeof(__proto__)]\n');assert.deepEqual(evaluateModel(symbols,'run'),[7,2],'source names and boundary lookup must also use own properties');
});
test('FED586 method receiver and source kinds refuse before JavaScript property operations',()=>{
  const bad=['return "abc".has("length")','return "abc".get("length",0)','return "abc".size()','return "abc".keys()','return "abc".duplicate()', 'var d := {}\n\td.merge([7],true)\n\treturn [d.size(),d.get("0",0)]','var d := {}\n\td.merge(null,true)\n\treturn d','var d := {}\n\td.merge("text",true)\n\treturn d','var a := []\n\ta.merge({"v":7},true)\n\treturn a','var a := [1]\n\ta.append_array({"v":7})\n\treturn a','return {}.is_valid_float()'];
  for(const body of bad)assert.throws(()=>evaluateModel(compile('func run() -> Variant:\n\t'+body+'\n'),'run'),/receiver|requires|source|kind/,body);
  for(const method of ['"abc".has("length")','d.merge([7],true)']){const ir=compile(`func run(flag: bool) -> int:\n\tvar d := {}\n\tif flag:\n\t\t${method}\n\treturn 9\n`);assert.equal(evaluateModel(ir,'run',[false]),9);assert.throws(()=>evaluateModel(ir,'run',[true]),/receiver|requires|source|kind/);}
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\tvar d := {"v":7}\n\td.merge({"x":8},true)\n\tvar a := [1]\n\ta.append_array([2])\n\treturn [d.has("x"),d.get("v"),d.size(),a,a.has(2),"1.5".is_valid_float()]\n'),'run'),[true,7,2,[1,2],true,true]);
});
test('PR120 4369307575 Array.has is Variant-type-sensitive scalar value membership',()=>{
  const ir=compile('func run() -> Array:\n\tvar a := [10,20,7,true,"Tag",null]\n\treturn [a.has(0),a.has(20),a.has(7),a.has(7.0),[7.0].has(7),[7.0].has(7.0),a.has(true),a.has(false),a.has("Tag"),a.has("tag"),a.has(null),[].has(0),7==7.0]\n');
  assert.deepEqual(evaluateModel(ir,'run'),[false,true,true,false,false,true,true,false,true,false,true,false,true]);
  assert.throws(()=>evaluateModel(compile('func run() -> bool:\n\treturn [[1]].has([1])\n'),'run'),/membership.*scalar|scalar.*membership/);
  const dynamic=compile('func run(x: Variant) -> bool:\n\treturn [7].has(x)\n');
  assert.equal(evaluateModel(dynamic,'run',[modelNumber(7,'int')]),true);assert.equal(evaluateModel(dynamic,'run',[modelNumber(7,'float')]),false);
  assert.throws(()=>evaluateModel(dynamic,'run',[7]),/membership.*provenance|provenance.*membership/);
  const guarded=compile('func run(flag: bool) -> Array:\n\tvar a := [7 if flag else 7.0]\n\tvar b := [1]\n\tif flag:\n\t\tb.append(20)\n\treturn [a.has(7),a.has(7.0),b.has(20),b.has(0)]\n');
  for(const [flag,hand]of [[true,[true,false,true,false]],[false,[false,true,false,false]]])assert.deepEqual(evaluateModel(guarded,'run',[flag]),hand);
});
test('PR120 4369307578 array iteration reads live later values with structural refusal',()=>{
  const source='func change(a: Array,x: bool) -> void:\n\tif x:\n\t\ta[1] = 9\nfunc run(x: bool) -> Array:\n\tvar a := [1,2]\n\tvar alias := a\n\tvar out := []\n\tfor item in a:\n\t\tout.append(item)\n\t\tchange(alias,x)\n\treturn out\n';
  for(const [x,hand]of [[true,[1,9]],[false,[1,2]]])assert.deepEqual(evaluateModel(compile(source),'run',[x]),hand);
  for(const mutation of ['a.append(3)','a.pop_back()','a.append(3)\n\t\ta.pop_back()'])assert.throws(()=>evaluateModel(compile(`func run() -> Array:\n\tvar a := [1,2]\n\tfor item in a:\n\t\t${mutation}\n\treturn a\n`),'run'),/iterable.*mutat|iterable.*resiz/);
});
test('PR120 4369307581 hex prefixes precede decimal exponent provenance',()=>{
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\treturn [typeof(0xEF),0xEF/2]\n'),'run'),[2,119]);
  const source='func run() -> Array:\n\treturn [typeof(0xef),0xef/2,typeof(0xE_F),0xE_F/2,typeof(1_000),1_000/2,typeof(1e2),1e2/2,typeof(1_0e1),1_0e1/2,typeof(1.0e-1),1.0e-1/2]\n';
  assert.deepEqual(evaluateModel(compile(source),'run'),[2,119,2,119,2,500,3,50,3,50,3,.05]);
  for(const bad of ['0xE__F','0x_EF','1__0','1_e2','1e_2'])assert.throws(()=>compile(`func run() -> Variant:\n\treturn ${bad}\n`));
});
test('PR120 4369307584 non-String dictionary keys refuse throughout literal access mutation methods merge',()=>{
  const bodies=['var d := {1:"number","1":"text"}\n\treturn [d.size(),d[1],d["1"]]', 'var d := {"1":7}\n\treturn d[1]', 'var d := {"1":7}\n\td[1] = 8\n\treturn d', 'return {"1":7}.has(1)', 'return {"1":7}.get(1,9)', 'var d := {}\n\td.merge({1:7},true)\n\treturn d','return 1 in {"1":7}'];
  for(const body of bodies)assert.throws(()=>evaluateModel(compile('func run() -> Variant:\n\t'+body+'\n'),'run'),/dictionary.*String|String.*dictionary/,body);
  for(const expression of ['d[x]','d.has(x)','d.get(x,9)']){const ir=compile(`func run(x: Variant) -> Variant:\n\tvar d := {"1":7}\n\treturn ${expression}\n`);assert.equal(evaluateModel(ir,'run',['1']),expression==='d.has(x)'?true:7);for(const x of [modelNumber(1,'int'),true,null])assert.throws(()=>evaluateModel(ir,'run',[x]),/dictionary.*String|String.*dictionary/);}
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\tvar d := {"1":7}\n\td["1"] = 8\n\td.merge({"s":9},true)\n\treturn [d["1"],d.has("s"),d.get("missing",3)]\n'),'run'),[8,true,3]);
});
test('source typeof returns integer Variant enums, including nested typeof',()=>{
  const ir=compile('func run() -> Array:\n\treturn [typeof(null),typeof(true),typeof(5),typeof(5.0),typeof("x"),typeof({}),typeof([]),typeof(typeof(5)),typeof(5)=="int",typeof(typeof(5))==TYPE_INT,TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_DICTIONARY,TYPE_ARRAY,typeof(TYPE_FLOAT)]\n');
  assert.deepEqual(evaluateModel(ir,'run'),[0,1,2,3,4,27,28,2,false,true,0,1,2,3,4,27,28,2]);
});
test('typed constants coerce before dependent initializers and preserve float provenance',()=>{
  const ir=compile('const A: float = 5\nconst B: int = -5.9\nconst C: float = B\nconst D = typeof(A)\nfunc run() -> Array:\n\treturn [A/2,typeof(A),B,C/2,typeof(C),D,typeof(D)]\n');
  assert.deepEqual(evaluateModel(ir,'run'),[2.5,3,-5,-2.5,3,3,2]);
  assert.throws(()=>evaluateModel(compile('const A: float = "5"\nfunc run() -> Variant:\n\treturn A\n'),'run'),/typed float/);
});
test('lerpf float signature survives integer operands and subsequent division',()=>{
  const ir=compile('func run(x: int) -> Array:\n\tvar a = lerpf(0,5,x)\n\treturn [a/2,typeof(a),typeof(a)==TYPE_FLOAT,typeof(typeof(a))]\n');
  for(const [x,v]of [[1,2.5],[0,0],[-1,-2.5],[2,5]])assert.deepEqual(evaluateModel(ir,'run',[x]),[v,3,true,2]);
  for(const name of ['lerpf','minf','maxf','roundf','signf','exp','log','tanh','pow']){const args=name==='lerpf'?'0,5,1':['pow','minf','maxf'].includes(name)?'1,2':'1';assert.deepEqual(evaluateModel(compile(`func run() -> Array:\n\treturn [typeof(${name}(${args})),typeof(typeof(${name}(${args})))]\n`),'run'),[3,2],name);}
});
test('strict unary and String arithmetic require admitted operand types',()=>{
  for(const op of ['-','+']){const ir=compile(`func run(x: Variant) -> Variant:\n\treturn ${op}x\n`);for(const v of [true,'5',null])assert.throws(()=>evaluateModel(ir,'run',[v]),/non-numeric unary/);assert.equal(evaluateModel(ir,'run',[modelNumber(5,'float')]),op==='-'?-5:5);}
  for(const expression of ['x + 1','1 + x','x - 1','x * 1'])assert.throws(()=>evaluateModel(compile(`func run(x: String) -> Variant:\n\treturn ${expression}\n`),'run',['abc']),/non-numeric/);
  assert.equal(evaluateModel(compile('func run(x: String) -> String:\n\treturn x + "!"\n'),'run',['abc']),'abc!');
});
test('deep duplicate disconnects conditional nested containers but preserves internal sharing',()=>{
  const ir=compile('func run(x: bool,y: bool) -> Array:\n\tvar a := [1]\n\tvar b := [2]\n\tvar d := {"v": {"a": a if x else b} if y else {"a": b if x else a}}\n\tvar deep := d.duplicate(true)\n\ta[0] = 9\n\tb[0] = 8\n\tvar z := [3]\n\tvar shared := {"a":z,"b":z}.duplicate(true)\n\tshared.a[0] = 7\n\treturn [deep.v.a[0],shared.b[0],z[0]]\n');
  for(const x of [true,false])for(const y of [true,false])assert.deepEqual(evaluateModel(ir,'run',[x,y]),[x===y?1:2,7,3]);
});
test('intrinsic coercions and type enums retain source numeric and Boolean categories',()=>{
  assert.deepEqual(evaluateModel(compile('func run() -> Array:\n\treturn [typeof(float(1)),typeof(int(1.5)),typeof(str(1)),typeof(is_finite(1.0)),typeof(range(2)),TYPE_FLOAT/2,typeof(TYPE_FLOAT/2)]\n'),'run'),[3,2,4,1,28,1,2]);
  for(const args of ['true,1,1','0,"5",1','0,5,false'])assert.throws(()=>evaluateModel(compile(`func run() -> Variant:\n\treturn lerpf(${args})\n`),'run'),/non-numeric math/);
  const original=compile('func run(x: bool) -> Array:\n\tvar a := [1]\n\tvar b := [2]\n\tvar d := {"a":a if x else b}\n\tvar deep := d.duplicate(true)\n\ta[0] = 9\n\tb[0] = 8\n\treturn deep.a\n');
  assert.deepEqual(evaluateModel(original,'run',[true]),[1]);assert.deepEqual(evaluateModel(original,'run',[false]),[2]);
});
test('ordered arithmetic and signed ties', () => {
  const ir = compile(unit('\treturn [roundf(x), int(x), 1.0 + x - x]'));
  assert.deepEqual(evaluateModel(ir, 'run', [-2.5]), [-3, -2, 1]);
});
test('typed integer division is distinct from floating division',()=>{
  const ir=compile(unit('\tvar a := -5\n\tvar b: float = -5.0\n\treturn [a / 2, b / 2]'));
  assert.deepEqual(evaluateModel(ir,'run',[0]),[-2,-2.5]);
  assert.throws(()=>compile(unit('\treturn true + 1')),/Boolean arithmetic/);
});
test('Variant/container arithmetic carries exact runtime numeric tags and rejects Boolean/unknown division',()=>{
  const source='func run() -> Array:\n\tvar a := [5,2]\n\tvar divided = a[0] / a[1]\n\ta[0] /= 2\n\tvar direct = 5\n\tvar floats := [5.0,2]\n\tvar d := {"v":5}\n\tvar copied := d.duplicate(true)\n\tcopied.merge({"f":5.0},true)\n\treturn [5/2,divided,a[0],direct/2,floats[0]/floats[1],copied.v/2,copied.f/2,[1,2,3,4,5].size()/2,typeof(a[0]) == TYPE_INT,typeof(floats[0]) == TYPE_FLOAT]\n';
  assert.deepEqual(evaluateModel(compile(source),'run'),[2,2,2,2,2.5,2,2.5,2,true,true]);
  for(const s of ['return [true][0] + 1','var a := [true]\n\ta[0] /= 2\n\treturn a[0]'])assert.throws(()=>evaluateModel(compile('func run() -> Variant:\n\t'+s+'\n'),'run'),/Boolean\/non-numeric/);
  const variant=compile('func run(x: Variant) -> Variant:\n\treturn x / 2\n');
  assert.equal(evaluateModel(variant,'run',[modelNumber(5,'int')]),2);assert.equal(evaluateModel(variant,'run',[modelNumber(5,'float')]),2.5);
  assert.throws(()=>evaluateModel(variant,'run',[5]),/unproved Variant/,'a raw external number is not guessed to be an integer');
  assert.equal(evaluateModel(variant,'run',[5],{numericInputs:'float'}),2.5,'explicit JSON-number float contract');
  const branch=compile('func run(x: float) -> Variant:\n\tvar a := [5]\n\tif x > 0:\n\t\ta[0] = 5.0\n\treturn a[0] / 2\n');
  assert.equal(evaluateModel(branch,'run',[1]),2.5);assert.equal(evaluateModel(branch,'run',[-1]),2);
});
test('typed compound division and assignments truncate signed mixed operands',()=>{
  for(const [left,right,expected] of [[5,2,2],[-5,2,-2],[5,-2,-2],[-5,-2,2],[5,2.0,2]]){
    for(const rhs of [String(right),right+'.0']){
      const ir=compile(`func run() -> int:\n\tvar a: int = ${left}\n\ta /= ${rhs}\n\treturn a\n`);
      assert.equal(evaluateModel(ir,'run'),expected);
    }
  }
  const ir=compile('func helper(x: int) -> int:\n\tx = -3.9\n\treturn x\nfunc run() -> Array:\n\tvar a: int = 5.9\n\ta += 0.9\n\tvar b: float = 5.0\n\tb /= 2\n\treturn [a, b, helper(7.8), 5 / 2, 5 / 2.0]\n');
  assert.deepEqual(evaluateModel(ir,'run'),[5,2.5,-3,2,2.5]);
  const target=compile('func index(counter: Array) -> int:\n\tcounter[0] += 1\n\treturn 0\nfunc run() -> Array:\n\tvar counter := [0]\n\tvar a := [5.0]\n\ta[index(counter)] /= 2.0\n\treturn [a[0],counter[0]]\n');assert.deepEqual(evaluateModel(target,'run'),[2.5,1]);
  assert.throws(()=>evaluateModel(compile(unit('\treturn int(x)')),'run',[2**53]),/exact backend integer/);
});
test('rounding preserves integral magnitudes, signed ties and adjacent fractions independently',()=>{
  for(const [value,expected] of [[2**52+1,2**52+1],[-(2**52+1),-(2**52+1)],[2**53-1,2**53-1],[.49999999999999994,0],[.5,1],[-.5,-1],[1.5,2],[-1.5,-2],[0,0],[-0,-0]])assert.equal(roundAway(value),expected);
});
test('ranking proof rejects helper-condition effects, aliases and every skipped lazy-pop path',()=>{
  const prefix='func move(a: Array, b: Array) -> bool:\n\tif not b.is_empty():\n\t\ta.append(b.pop_back())\n\treturn true\n';
  assert.throws(()=>compile(prefix+'func run() -> int:\n\tvar a := [1]\n\tvar b := [2]\n\twhile not a.is_empty():\n\t\tvar removed := a.pop_back()\n\t\tif move(a,b):\n\t\t\tvar ignored := 1\n\treturn a.size()\n'),/decreasing/);
  for(const expression of ['a.pop_back() if x > 0 else 0.0','x > 0 and a.pop_back() > 0','x <= 0 or a.pop_back() > 0','[a]'])assert.throws(()=>compile(unit(`\tvar a := [1]\n\twhile not a.is_empty():\n\t\tvar removed := ${expression}\n\treturn a.size()`)),/decreasing/);
  assert.throws(()=>compile(unit('\tvar a := [1]\n\tvar alias := a\n\twhile not a.is_empty():\n\t\tvar v := a.pop_back()\n\t\talias.append(v)\n\treturn a.size()')),/decreasing/);
});
test('lazy branches do not evaluate errors', () => {
  const ir = compile(unit('\treturn log(x) if x > 0 else 7.0'));
  assert.equal(evaluateModel(ir, 'run', [-1]), 7);
});
test('array aliases, dictionary merges and bounded loops', () => {
  const ir = compile(unit('\tvar a := [1.0, 2.0]\n\tvar b := a\n\tb[0] += x\n\tvar d := {"a": a}\n\td.merge({"z": false}, true)\n\tfor i in range(2):\n\t\ta[i] *= 2.0\n\treturn d'));
  assert.deepEqual(evaluateModel(ir, 'run', [3]), { a: [8, 4], z: false });
});
test('unsupported reachable calls and unproved loops reject', () => {
  assert.throws(() => compile(unit('\treturn fetch(x)')), /unresolved|unsupported/i);
  assert.throws(() => compile(unit('\twhile x > 0:\n\t\tx -= 1\n\treturn x')), /loop|bound/i);
  assert.throws(() => compile(unit('\treturn missing_name')), /unresolved variable/);
  assert.throws(() => compile('func run() -> float:\n\treturn run()\n'),/recursive/);
  assert.throws(() => compile(unit('\treturn pow(x)')),/argument count/);
  assert.throws(() => compile(unit('\tvar a := [1]\n\treturn a.slice(0, 1, 2)')),/argument count/);
  assert.throws(() => compile(unit('\treturn 9007199254740993')),/exact backend integer/);
});
test('canonical dependency graph compiles without I/O execution', () => {
  const source = fs.readFileSync(new URL('../../game/model/economy.gd', import.meta.url), 'utf8');
  const ir = compileModel(source);
  assert.equal(ir.coverage.functions.length, 24);
  assert.ok(ir.coverage.functions.includes('_principal_net'));
  assert.ok(ir.coverage.functions.includes('_validate_state'));
  assert.deepEqual(ir.coverage.boundaries, ['load_portfolio_reference']);
  assert.throws(()=>compileModel(source,{boundaries:{_principal_net:{input:'fake',validator:'_validate_state'}}}),/input-only/);
  assert.throws(()=>compileModel(source.replace('return parsed if valid.ok else valid','return {"ok":true,"value":parsed.value}')),/boundary.*changed/);
  const restored=JSON.parse(JSON.stringify(ir));assert.deepEqual(restored.coverage.functions,ir.coverage.functions);
  assert.equal(evaluateModel(restored,'annualized_growth',[102,100]),evaluateModel(ir,'annualized_growth',[102,100]));
});
console.log(`PASS: ${checks} compiler tests; pure only`);
