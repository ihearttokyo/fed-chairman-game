import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { compileModel, evaluateModel, modelConstants, modelNumber, isModelNumber, numericKind } from '../spreadsheet/model-compiler.mjs';
import { emitExcel } from '../spreadsheet/model-excel.mjs';

const text = expression => `func run(x: float) -> float:\n\treturn ${expression}\n`;
const bindings = { entrypoint: 'run', arguments: { x: { cell: "'Policy'!A1", type: 'number' } },outputs:{result:"'Economy'!E20"} };
const a = emitExcel(compileModel(text('x * 2.0'), { entrypoints: ['run'] }), bindings);
const b = emitExcel(compileModel(text('x * 3.0'), { entrypoints: ['run'] }), bindings);
assert.notDeepEqual(a.formulas, b.formulas, 'canonical source edit must automatically change emission');
assert.ok(a.sourceMap.length > 0);
assert.ok(a.provenance.canonicalSourceSha256);
assert.ok(!Object.values(a.formulas).some(x => /LAMBDA|INDIRECT|OFFSET|WEBSERVICE/i.test(x)));
console.log('PASS: source edit, source-to-cell provenance and ordinary formula dialect');

// Independent, small formula parser/evaluator for generated scalar syntax. This
// is simulated Excel arithmetic, NOT Artifact Tool/Excel/Calc recalculation.
class CellError extends Error {}
function formulaAST(text) {
  const tokens=[];let p=0;
  while(p<text.length){const s=text.slice(p),m=s.match(/^(?:\s+|"(?:[^"]|"")*"|'[^']+'!\$?[A-Z]+\$?\d+|[A-Z]+\d+|(?:\d+(?:\.\d*)?|\.\d+)(?:E[+-]?\d+)?|[A-Z_]+|<=|>=|<>|.)/i);if(!m)throw Error(s);p+=m[0].length;if(m[0].trim())tokens.push(m[0]);}
  let i=0;if(tokens[i]==='=')i++;
  const take=x=>{const t=tokens[i++];assert.ok(x===undefined||t===x,`Expected ${x}, got ${t}`);return t;};
  function expression(min=0){let t=take(),left;
    if(t==='-'||t==='+')left={unary:t,arg:expression(45)};
    else if(t==='('){left=expression();take(')');}
    else if(t.startsWith('"'))left={literal:t.slice(1,-1).replaceAll('""','"')};
    else if(/^\d|^\.\d/.test(t))left={literal:Number(t)};
    else if(t==='TRUE'||t==='FALSE')left={literal:t==='TRUE'};
    else if(tokens[i]==='('){take('(');const args=[];if(tokens[i]!==')')for(;;){args.push(expression());if(tokens[i]!==',')break;take(',');}take(')');left={call:t,args};}
    else left={cell:t};
    for(;;){const op=tokens[i],prec=({'&':5,'=':10,'<>':10,'<':10,'>':10,'<=':10,'>=':10,'+':20,'-':20,'*':30,'/':30,'^':40})[op];if(prec===undefined||prec<min)break;i++;left={op,left,right:expression(prec+1)};}return left;
  }
  const tree=expression();assert.equal(i,tokens.length,`Trailing formula tokens: ${text}`);return tree;
}
function evaluate(program, inputs={}, options={}) {
  const cache=new Map(Object.entries(inputs));
  const finite=n=>{if(!Number.isFinite(n))throw new CellError('#NUM!');return n;};
  const cell=name=>{if(!cache.has(name)){if(!Object.hasOwn(program.formulas,name))throw Error('Missing test binding '+name);try{cache.set(name,run(formulaAST(program.formulas[name])));}catch(e){if(!(e instanceof CellError))throw e;cache.set(name,e);}}const value=cache.get(name);if(value instanceof CellError)throw value;return value;};
  const run=n=>{
    if(Object.hasOwn(n,'literal'))return n.literal;if(n.cell)return cell(n.cell);if(n.unary)return finite(n.unary==='-'?-run(n.arg):+run(n.arg));
    if(n.op){const a=run(n.left),b=run(n.right),aa=typeof a==='string'?a.toLowerCase():a,bb=typeof b==='string'?b.toLowerCase():b;switch(n.op){case '+':return finite(a+b);case '-':return finite(a-b);case '*':return finite(a*b);case '/':if(b===0)throw new CellError('#DIV/0!');return finite(a/b);case '^':return finite(a**b);case '&':return String(a)+String(b);case '=':return aa===bb;case '<>':return aa!==bb;case '<':return aa<bb;case '>':return aa>bb;case '<=':return aa<=bb;case '>=':return aa>=bb;}}
    const name=n.call,a=n.args;
    if(name==='IF'){const value=run(a[0])?run(a[1]):run(a[2]);return value===null&&options.coerceBlankSelections?0:value;}
    if(name==='IFERROR'){try{return run(a[0]);}catch(e){if(!(e instanceof CellError))throw e;return run(a[1]);}}
    if(name==='NA')throw new CellError('#N/A');
    if(['ISNUMBER','ISLOGICAL','ISBLANK'].includes(name)){let v;try{v=run(a[0]);}catch(e){if(e instanceof CellError)return false;throw e;}return name==='ISNUMBER'?typeof v==='number':name==='ISLOGICAL'?typeof v==='boolean':v===null;}
    if(name==='MIN'||name==='MAX'){const numbers=[];for(const node of a){const v=run(node);if(node.cell&&typeof v!=='number')continue;const n=typeof v==='boolean'?Number(v):Number(v);if(!Number.isFinite(n))throw new CellError('#VALUE!');numbers.push(n);}return numbers.length?(name==='MIN'?Math.min(...numbers):Math.max(...numbers)):0;}
    const v=a.map(run);switch(name){case 'NOT':return !v[0];case 'EXACT':return String(v[0])===String(v[1]);case 'ABS':return Math.abs(v[0]);case 'SIGN':return Math.sign(v[0]);case 'INT':return Math.floor(v[0]);case 'ROUND':return finite(Math.sign(v[0])*Math.round(Math.abs(v[0])*10**v[1])/10**v[1]);case 'MIN':return Math.min(...v);case 'MAX':return Math.max(...v);case 'EXP':return finite(Math.exp(v[0]));case 'LN':return finite(Math.log(v[0]));case 'TANH':return Math.tanh(v[0]);case 'POWER':return finite(Math.pow(...v));default:throw Error('Unsupported generated formula '+name);}
  };
  for(const name of Object.keys(program.formulas)){try{cell(name);}catch(e){if(!(e instanceof CellError))throw e;}}
  return {output(path){try{return run(formulaAST(program.outputs[path]));}catch(e){if(!(e instanceof CellError))throw e;return e.message;}},cache};
}
const micro = (source,args,values={}) => {
  const ir=compileModel(source,{entrypoints:['run']});const program=emitExcel(ir,{entrypoint:'run',arguments:args});return {program,computed:evaluate(program,values)};
};
let checks=1;
const emittedFunctions=new Set();
const recordCoverage=program=>program.coverage.functions.forEach(name=>emittedFunctions.add(name));
const test=(name,run)=>{if(process.env.FED_MODEL_TEST_FILTER&&!name.includes(process.env.FED_MODEL_TEST_FILTER))return;run();checks++;console.log('PASS '+name);};
// BEGIN FED597 additions: native4.7.2 receiver -> RHS -> index -> read/write.
// Source: /private/tmp/fed596-language-oracle/project/oracle.gd
// result.json SHA256: 15ec4ef21c886c9cb40a1524e113f9d9ad6f814930a1e1a48c45abb31df2e9bf
const nativeSource597="extends SceneTree\nfunc _receiver(a: Array, events: Array) -> Array:\n\tevents.append(\"receiver\")\n\treturn a\nfunc _index(events: Array, index: int) -> int:\n\tevents.append(\"index\")\n\treturn index\nfunc _rhs(a: Array, events: Array) -> Variant:\n\tevents.append(\"rhs\")\n\treturn a.pop_back()\nfunc assignment(index: int, compound: bool) -> Dictionary:\n\tvar a := [1, 7]\n\tvar events: Array = []\n\tif compound:\n\t\t_receiver(a, events)[_index(events, index)] += _rhs(a, events)\n\telse:\n\t\t_receiver(a, events)[_index(events, index)] = _rhs(a, events)\n\treturn {\"array\": a, \"events\": events}\nfunc order(flag: bool) -> Array:\n\tvar d := {}\n\tif flag:\n\t\td[\"2\"] = \"two\"\n\t\td[\"1\"] = \"one\"\n\telse:\n\t\td[\"1\"] = \"one\"\n\t\td[\"2\"] = \"two\"\n\tvar out: Array = []\n\tfor k in d:\n\t\tout.append(k)\n\treturn out\nfunc run(i: int, c: bool) -> Dictionary:\n\treturn assignment(i,c)\n";
const nativeCases597=[{"index":0,"compound":false,"expected":{"array":[7],"events":["receiver","rhs","index"]}},{"index":0,"compound":true,"expected":{"array":[8],"events":["receiver","rhs","index"]}},{"index":-1,"compound":false,"expected":{"array":[7],"events":["receiver","rhs","index"]}},{"index":-1,"compound":true,"expected":{"array":[8],"events":["receiver","rhs","index"]}}];
const receiverRhsIndex597=op=>'func receiver(holder: Dictionary,e: Array) -> Array:\n\te.append("receiver")\n\treturn holder.a\nfunc rhs(a: Array,holder: Dictionary,e: Array) -> int:\n\te.append("rhs")\n\ta[0] = 99\n\tholder.a = [1000]\n\treturn a[0]\nfunc index(a: Array,e: Array) -> int:\n\te.append("index")\n\ta[0] = 100.0\n\treturn 0\nfunc run() -> Array:\n\tvar a := [7]\n\tvar holder := {"a":a}\n\tvar e := []\n\treceiver(holder,e)[index(a,e)] '+op+' rhs(a,holder,e)\n\treturn [a[0],typeof(a[0]),holder.a[0],e]\n';
const emptyGrowth597=(op,index,erase=false)=>'func receiver(a: Array,e: Array) -> Array:\n\te.append("receiver")\n\treturn a\nfunc rhs(a: Array,e: Array) -> int:\n\te.append("rhs")\n\ta.append(5)\n\treturn 3\nfunc index(a: Array,e: Array) -> int:\n\te.append("index")\n\t'+(erase?'a.resize(0)':'a.append(9)')+'\n\treturn '+index+'\nfunc run() -> Array:\n\tvar a := []\n\tvar e := []\n\treceiver(a,e)[index(a,e)] '+op+' rhs(a,e)\n\treturn [a,e]\n';
const member597=(key,indexed)=>'func receiver(d: Dictionary,e: Array) -> Dictionary:\n\te.append("receiver")\n\treturn d\nfunc rhs(d: Dictionary,e: Array) -> int:\n\te.append("rhs")\n\td["'+key+'"] = 9.0\n\treturn 2\nfunc index(d: Dictionary,e: Array) -> String:\n\te.append("index")\n\td["'+key+'"] = 12.0\n\treturn "'+key+'"\nfunc run() -> Array:\n\tvar d := {}\n\tvar e := []\n\treceiver(d,e)'+(indexed?'[index(d,e)]':'.'+key)+' /= rhs(d,e)\n\treturn [d["'+key+'"],typeof(d["'+key+'"]),e]\n';
const flatten597=(v,p='',out={})=>{if(Array.isArray(v))v.forEach((x,i)=>flatten597(x,`${p||'result'}[${i}]`,out));else if(v&&typeof v==='object')for(const [key,x]of Object.entries(v))flatten597(x,p?p+'.'+key:key,out);else out[p||'result']=v;return out;};
const nativeHand597=(program,values,expected)=>{const want=flatten597(expected),actual=evaluate(program,values,{coerceBlankSelections:true});for(const [path,value]of Object.entries(want))assert.equal(actual.output(path),value,path);for(const path of Object.keys(program.outputs))if(!Object.hasOwn(want,path))assert.equal(actual.output(path),'#N/A','unavailable capacity '+path);};
const numericTag597=(p,values,d)=>{if(typeof d==='string')return d;const condition=evaluate({...p,outputs:{tag:'='+d.condition}},values).output('tag');assert.equal(typeof condition,'boolean','numeric tag guard must be available');return numericTag597(p,values,condition?d.yes:d.no);};
test('FED597 actual native assignment outputs and event order match both formula modes',()=>{
  const ir=compileModel(nativeSource597,{entrypoints:['run']});for(const optimize of [true,false]){const p=emitExcel(ir,{entrypoint:'run',optimize,arguments:{i:{cell:"'Policy'!E6",type:'number',numericType:'int'},c:{cell:"'Policy'!E7",type:'boolean'}}});for(const row of nativeCases597){const values={"'Policy'!E6":row.index,"'Policy'!E7":row.compound};nativeHand597(p,values,row.expected);assert.equal(numericTag597(p,values,p.outputNumericTypes['array[0]']),'int');}}
});
test('FED597 captured receiver RHS value and post-index target type survive both modes',()=>{
  for(const optimize of [true,false])for(const op of ['=','+='])nativeHand597(emitExcel(compileModel(receiverRhsIndex597(op),{entrypoints:['run']}),{entrypoint:'run',optimize}),{},[op==='='?99:199,op==='='?2:3,1000,['receiver','rhs','index']]);
});
test('FED597 initially empty Array live growth and index side effects preserve ownership',()=>{
  for(const optimize of [true,false])for(const op of ['=','+=']){
    for(const i of ['0','-1'])nativeHand597(emitExcel(compileModel(emptyGrowth597(op,i),{entrypoints:['run']}),{entrypoint:'run',optimize}),{},[i==='0'?[op==='='?3:8,9]:[5,op==='='?3:12],['receiver','rhs','index']]);
    const p=emitExcel(compileModel(emptyGrowth597(op,'0',true),{entrypoints:['run']}),{entrypoint:'run',optimize});for(const path of Object.keys(p.outputs))assert.equal(evaluate(p).output(path),'#N/A');
  }
});
test('FED597 legal Dictionary members and indices read post-RHS post-index numeric tags',()=>{
  for(const optimize of [true,false])for(const key of ['value','numericType','__proto__','constructor','toString'])for(const indexed of [true,false])nativeHand597(emitExcel(compileModel(member597(key,indexed),{entrypoints:['run']}),{entrypoint:'run',optimize}),{},[indexed?6:4.5,3,indexed?['receiver','rhs','index']:['receiver','rhs']]);
});
test('FED597 typed name assignments preserve integer truncation float provenance and RHS events',()=>{
  const source='func rhs(e: Array) -> float:\n\te.append("rhs")\n\treturn 2.0\nfunc run() -> Array:\n\tvar e := []\n\tvar n: int = 7\n\tn /= rhs(e)\n\tvar f: float = 7.0\n\tf /= rhs(e)\n\treturn [n,typeof(n),f,typeof(f),e]\n';for(const optimize of [true,false])nativeHand597(emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},[3,2,3.5,3,['rhs','rhs']]);
});
test('FED597 lazy assignments preserve event absence and receiver refusals in both modes',()=>{
  const source=nativeSource597+'func guarded(flag: bool,i: int,c: bool) -> Dictionary:\n\tvar a := [1,7]\n\tvar e := []\n\tif flag:\n\t\tif c:\n\t\t\t_receiver(a,e)[_index(e,i)] += _rhs(a,e)\n\t\telse:\n\t\t\t_receiver(a,e)[_index(e,i)] = _rhs(a,e)\n\treturn {"array":a,"events":e}\n';
  for(const optimize of [true,false]){const ir=compileModel(source,{entrypoints:['guarded']}),p=emitExcel(ir,{entrypoint:'guarded',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'},i:{cell:"'Policy'!E7",type:'number',numericType:'int'},c:{cell:"'Policy'!E8",type:'boolean'}}});for(const row of nativeCases597)for(const flag of [true,false])nativeHand597(p,{"'Policy'!E6":flag,"'Policy'!E7":row.index,"'Policy'!E8":row.compound},flag?row.expected:{array:[1,7],events:[]});}
});
// END FED597 additions.

// BEGIN FED596 additions; all prior120 groups remain byte-identical below.
const hand596=(p,values,expected)=>{const got=evaluate(p,values,{coerceBlankSelections:true});for(const [key,value]of Object.entries(expected))assert.equal(got.output(key),value,key);};
const array596=expected=>Object.fromEntries(expected.map((v,i)=>[`result[${i}]`,v]));
test('FED596 live Array write emptying RHS stays unavailable in both formula modes',()=>{
  for(const optimize of [true,false])for(const op of ['=','+='])for(const receiver of ['a','alias','holder.a'])for(const rhs of ['a','alias','holder.a']){
    const s=`func run() -> Array:\n\tvar a := [7]\n\tvar alias := a\n\tvar holder := {"a":a}\n\t${receiver}[0] ${op} ${rhs}.pop_back()\n\treturn [a.size(),a[0]]\n`,p=emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize});hand596(p,{},array596(['#N/A','#N/A']));
  }
});
test('FED596 native post-RHS Array values preserve valid writes and NIL arithmetic refusal',()=>{
  for(const optimize of [true,false])for(const [op,shrink,grow,regrow]of [['=',11,5,3],['+=',18,12,null]]){
    const sources=[`func run() -> Array:\n\tvar a := [7,11]\n\ta[0] ${op} a.pop_back()\n\treturn [a.size(),a[0]]\n`,`func grow(a: Array) -> int:\n\ta.append(9)\n\treturn 5\nfunc run() -> Array:\n\tvar a := [7]\n\tvar alias := a\n\ta[0] ${op} grow(alias)\n\treturn [a.size(),a[0],a[1]]\n`,`func regrow(a: Array) -> int:\n\ta.pop_back()\n\ta.resize(1)\n\treturn 3\nfunc run() -> Array:\n\tvar a := [7]\n\ta[0] ${op} regrow(a)\n\treturn [a.size(),a[0],typeof(a[0])]\n`];
    sources.forEach((s,i)=>hand596(emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array596(i===2&&op==='+='?['#N/A','#N/A','#N/A']:[[1,shrink],[2,grow,9],[1,regrow,2]][i])));hand596(emitExcel(compileModel(sources[2].replace('a[0] '+op,'a[-1] '+op),{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array596(op==='+='?['#N/A','#N/A','#N/A']:[1,regrow,2]));
  }
});
test('FED596 native RHS precedes index and compound target read',()=>{
  const source='func receiver(a: Array,c: Array) -> Array:\n\tc[0] += 1\n\treturn a\nfunc index(c: Array) -> int:\n\tc[1] += 1\n\treturn 0\nfunc rhs(a: Array,c: Array) -> int:\n\tc[2] += 1\n\ta[0] = 99\n\treturn 1\nfunc run() -> Array:\n\tvar a := [7]\n\tvar c := [0,0,0]\n\treceiver(a,c)[index(c)] += rhs(a,c)\n\treturn [a[0],c[0],c[1],c[2]]\n';
  const mutation='func index(a: Array,c: Array) -> int:\n\tc[0] += 1\n\ta.pop_back()\n\treturn -1\nfunc run() -> Array:\n\tvar a := [7,11]\n\tvar c := [0]\n\ta[index(a,c)] = 3\n\treturn [a.size(),a[0],c[0]]\n';
  for(const optimize of [true,false])for(const [s,expected]of [[source,[100,1,1,1]],[mutation,[1,3,1]]])hand596(emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array596(expected));
});
test('FED596 native live negative normalization supports final valid bounds',()=>{
  for(const optimize of [true,false])for(const op of ['=','+=']){
    const shrink=`func run() -> Array:\n\tvar a := [7,11]\n\tvar alias := a\n\ta[-1] ${op} alias.pop_back()\n\treturn [a.size(),a[0]]\n`,grow=`func grow(a: Array) -> int:\n\ta.append(9)\n\treturn 5\nfunc run() -> Array:\n\tvar a := [7,11]\n\ta[-1] ${op} grow(a)\n\treturn [a.size(),a[0]]\n`;
    for(const [s,expected] of [[shrink,[1,op==='='?11:18]],[grow,[3,7]]])hand596(emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array596(expected));
    const plain=`func run() -> Array:\n\tvar a := [7,11]\n\ta[-1] ${op} 3\n\treturn a\n`;hand596(emitExcel(compileModel(plain,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array596([7,op==='='?3:14]));
  }
  const initial='func grow(a: Array) -> int:\n\ta.append(9)\n\treturn 5\nfunc run() -> Array:\n\tvar a := [7]\n\ta[1] = grow(a)\n\treturn [a.size(),a[0]]\n';for(const optimize of [true,false])hand596(emitExcel(compileModel(initial,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array596([2,7]));
});
test('FED596 native live writes preserve inactive branches',()=>{
  for(const optimize of [true,false])for(const op of ['=','+=']){
    const s=`func run(flag: bool) -> Array:\n\tvar a := [7]\n\tif flag:\n\t\ta[0] ${op} a.pop_back()\n\treturn [a.size(),a[0]]\n`,p=emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand596(p,{"'Policy'!E6":false},array596([1,7]));hand596(p,{"'Policy'!E6":true},array596(['#N/A','#N/A']));
    const n=`func run(flag: bool) -> Array:\n\tvar a := [7,11]\n\ta[-1] ${op} (a.pop_back() if flag else 3)\n\treturn [a.size(),a[0],a[-1]]\n`,q=emitExcel(compileModel(n,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand596(q,{"'Policy'!E6":false},array596([2,7,op==='='?3:14]));hand596(q,{"'Policy'!E6":true},array596([1,op==='='?11:18,op==='='?11:18]));
  }
  for(const optimize of [true,false]){
    for(const index of ['0','-1'])for(const op of ['=','+=']){const s=`func run(flag: bool) -> Array:\n\tvar a := [7]\n\tvar b := [11]\n\tvar target = a if flag else b\n\ttarget[${index}] ${op} a.pop_back()\n\treturn [a.size(),b.size(),b[0]]\n`,p=emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand596(p,{"'Policy'!E6":false},array596([0,1,op==='='?7:18]));hand596(p,{"'Policy'!E6":true},array596(['#N/A','#N/A','#N/A']));}
    const s='func grow(a: Array) -> int:\n\ta.append(9)\n\treturn 5\nfunc run(flag: bool) -> Array:\n\tvar a := [7]\n\tif flag:\n\t\ta[1] = grow(a)\n\treturn [a.size(),a[0]]\n',p=emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand596(p,{"'Policy'!E6":false},array596([1,7]));hand596(p,{"'Policy'!E6":true},array596([2,7]));
  }
});
test('FED596 Dictionary creation order overwrites and compound reads are unchanged',()=>{
  const source='func create(d: Dictionary) -> int:\n\td.numericType = 5\n\treturn 7\nfunc overwrite(d: Dictionary) -> int:\n\td.value = 99\n\treturn 1\nfunc run() -> Array:\n\tvar d := {}\n\td.value = create(d)\n\td.value += overwrite(d)\n\treturn [d.keys(),d.value,d.numericType]\n';
  for(const optimize of [true,false])hand596(emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},{'result[0][0]':'numericType','result[0][1]':'value','result[1]':100,'result[2]':5});
});
// END FED596 additions.

// BEGIN FED594 additions; all prior108 groups remain byte-identical below.
const hand594=(p,values,expected)=>{const got=evaluate(p,values,{coerceBlankSelections:true});for(const [key,value]of Object.entries(expected))assert.equal(got.output(key),value,key);};
const array594=expected=>Object.fromEntries(expected.map((v,i)=>[`result[${i}]`,v]));
test('FED594 numeric receiver member and index reads remain unavailable in both modes',()=>{
  for(const optimize of [true,false])for(const literal of ['7','7.0'])for(const access of ['.value','.numericType','["value"]','["numericType"]']){
    hand594(emitExcel(compileModel(`func run() -> Variant:\n\treturn (${literal})${access}\n`,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},{result:'#N/A'});
    hand594(emitExcel(compileModel(`func run(v: Variant) -> Variant:\n\treturn v${access}\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{v:modelNumber(7,literal==='7'?'int':'float')}}),{},{result:'#N/A'});
  }
});
test('FED594 numeric receiver lazy reads preserve inactive and valid conditional Dictionary arms',()=>{
  for(const optimize of [true,false])for(const literal of ['7','7.0'])for(const access of ['.value','.numericType','["value"]','["numericType"]']){
    const p=emitExcel(compileModel(`func run(flag: bool) -> Variant:\n\tvar v := ${literal}\n\treturn v${access} if flag else "safe"\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand594(p,{"'Policy'!E6":false},{result:'safe'});hand594(p,{"'Policy'!E6":true},{result:'#N/A'});
    const key=access.includes('numericType')?'numericType':'value',q=emitExcel(compileModel(`func run(flag: bool) -> Variant:\n\tvar v = ${literal} if flag else {"${key}":"visible"}\n\treturn v${access}\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand594(q,{"'Policy'!E6":false},{result:'visible'});hand594(q,{"'Policy'!E6":true},{result:'#N/A'});
  }
  for(const optimize of [true,false])hand594(emitExcel(compileModel('func run() -> Array:\n\tif false:\n\t\tvar hidden = (7).value\n\treturn [false and (7).value>0,true or (7.0).value>0,(7).numericType if false else "safe"]\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array594([false,true,'safe']));
});
test('FED594 numeric receiver writes and compounds remain unavailable only when active',()=>{
  for(const optimize of [true,false])for(const literal of ['7','7.0'])for(const access of ['.value','.numericType','["value"]','["numericType"]'])for(const op of ['=','+=']){
    const p=emitExcel(compileModel(`func run(flag: bool) -> String:\n\tvar v := ${literal}\n\tif flag:\n\t\tv${access} ${op} 1\n\treturn "safe"\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand594(p,{"'Policy'!E6":false},{result:'safe'});hand594(p,{"'Policy'!E6":true},{result:'#N/A'});
  }
  for(const optimize of [true,false])for(const literal of ['7','7.0'])for(const access of ['.value','.numericType','["value"]','["numericType"]'])for(const op of ['=','+=']){
    const key=access.includes('numericType')?'numericType':'value',p=emitExcel(compileModel(`func run(flag: bool) -> Variant:\n\tvar v = ${literal} if flag else {"${key}":5}\n\tv${access} ${op} 1\n\treturn v${access}\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand594(p,{"'Policy'!E6":false},{result:op==='='?1:6});hand594(p,{"'Policy'!E6":true},{result:'#N/A'});
  }
});
test('FED594 legal Dictionary value numericType and prototype-like keys are not blacklisted',()=>{
  const s='func run() -> Array:\n\tvar d := {"value":7,"numericType":"int","__proto__":2,"constructor":"ctor","toString":"text"}\n\tvar alias := d\n\talias.value += 1\n\td["numericType"] = "float"\n\talias.__proto__ += 3\n\td["constructor"] = "new"\n\td.toString = "kept"\n\treturn [d.value,d["value"],d.numericType,d["numericType"],d.__proto__,d["__proto__"],d.constructor,d.toString,d.get("value"),d.has("numericType"),d.size()]\n';
  for(const optimize of [true,false])hand594(emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array594([8,8,'float','float',5,5,'new','kept',8,true,5]));
});
test('FED594 admitted Array indices and existing method dispatch retain hand expectations',()=>{
  const s='func run(i: int) -> Array:\n\tvar a := [2,4,null]\n\tvar alias := a\n\talias[-3] += 1\n\ta[1] = 8\n\treturn [a[0],a[-2],a.get(-3),a.get(1),a[i],a[0.0],a.get(-2.0),a.size(),a.has(8),a[-1]==null,"7.5".is_valid_float()]\n';
  for(const optimize of [true,false]){const p=emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{i:{cell:"'Policy'!E6",type:'number',numericType:'int'}}});for(const [i,value]of [[0,3],[1,8],[-3,3],[-2,8]])hand594(p,{"'Policy'!E6":i},array594([3,8,3,8,value,3,8,3,true,true,true]));}
});
test('FED594 unsupported receiver and index domains remain unavailable or explicit compile refusal',()=>{
  const expressions=['(true).length','(null).length','("abc").length','([1,2]).length','(true)["0"]','(null)["0"]','("abc")["0"]'];
  for(const optimize of [true,false]){
    for(const expr of expressions)hand594(emitExcel(compileModel(`func run() -> Variant:\n\treturn ${expr}\n`,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},{result:'#N/A'});
    for(const value of ['true','null','"abc"','[1,2]'])hand594(emitExcel(compileModel(`func run() -> int:\n\tvar v = ${value}\n\tv.length = 1\n\treturn 9\n`,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},{result:'#N/A'});

    for(const index of ['"0"','"length"','true','null','0.5','3','-4','INF','NAN'])for(const use of [`return a[${index}]`,`a[${index}] = 9\n\treturn 1`,`a[${index}] += 1\n\treturn 1`,`return a.get(${index})`])hand594(emitExcel(compileModel('func run() -> Variant:\n\tvar a := [1,2,3]\n\t'+use+'\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),{},{result:'#N/A'});
    for(const index of ['0','true','null'])assert.throws(()=>emitExcel(compileModel(`func run() -> Variant:\n\treturn {"0":"zero"}[${index}]\n`,{entrypoints:['run']}),{entrypoint:'run',optimize}),e=>e.name==='ModelCompileError'&&/dictionary key must be String/.test(e.message));
    for(const value of ['7','7.0'])hand594(emitExcel(compileModel(`func run() -> Variant:\n\treturn (${value}).get(0)\n`,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},{result:'#N/A'});
  }
});
// END FED594 additions.

// BEGIN FED593 additions; all prior93 groups remain byte-identical below.
const hand593=(p,values,expected)=>{const got=evaluate(p,values,{coerceBlankSelections:true});for(const [key,value]of Object.entries(expected))assert.equal(got.output(key),value,key);};
const array593=expected=>Object.fromEntries(expected.map((v,i)=>[`result[${i}]`,v]));
test('FED593 str simple source literals are hand-derived not shared parity',()=>{
  const s='func run() -> Array:\n\treturn [str(null),str(true),str(false),str(7),str(7.0),str(-7),str(-7.0),str(0),str(0.0),str("MiXeD"),str("7.00"),typeof(str(1)),typeof(str(null)),str(7)==str(7.0),str(1e0),str(1000000.0)]\n';
  for(const optimize of [true,false]){const p=emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize});hand593(p,{},array593(['<null>','true','false','7','7.0','-7','-7.0','0','0.0','MiXeD','7.00',4,4,false,'1.0','1000000.0']));}
});
test('FED593 str typed constants casts and canonical metadata remain correct',()=>{
  for(const optimize of [true,false]){
    const p=emitExcel(compileModel('const S = str(7.0)\nfunc run() -> Array:\n\treturn [S,str(float(7)),str(int(7.0)),str(7/2),str(7.0+0.0)]\n',{entrypoints:['run']}),{entrypoint:'run',optimize});hand593(p,{},array593(['7.0','7.0','7','3','7.0']));
    const row={key:'policy_rate',source:'https://example.invalid/Source',unit:'Percent',description:'CaSe and "quotes"',id:'scenario_id'};
    const q=emitExcel(compileModel('func run(row: Dictionary) -> Array:\n\treturn [str(row.key),str(row.source),str(row.unit),str(row.description),str(row.id)]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{row}});hand593(q,{},array593(Object.values(row)));
  }
});
test('FED593 str unqualified numeric formatting stays unavailable including unknown provenance',()=>{
  for(const optimize of [true,false]){
    for(const value of ['0.1','7.5','-0.0','1000001.0','INF','NAN']){const p=emitExcel(compileModel(`func run() -> String:\n\treturn str(${value})\n`,{entrypoints:['run']}),{entrypoint:'run',optimize});hand593(p,{},{result:'#N/A'});assert.ok(p.diagnostics.some(d=>d.kind==='unavailable-guard'));}
    const ir=compileModel('func run(v: Variant) -> String:\n\treturn str(v)\n',{entrypoints:['run']});
    for(const [v,expected]of [[modelNumber(7,'int'),'7'],[modelNumber(7,'float'),'7.0'],[7,'#N/A'],[modelNumber(7,'unknown'),'#N/A']])hand593(emitExcel(ir,{entrypoint:'run',optimize,arguments:{v}}),{},{result:expected});
    hand593(emitExcel(ir,{entrypoint:'run',optimize,numericInputs:'float',arguments:{v:7}}),{},{result:'7.0'});
    for(const binding of [{type:'number'},{type:'number',numericType:'int'},{type:'number',numericType:'float'},{type:'variant'}]){const p=emitExcel(ir,{entrypoint:'run',optimize,arguments:{v:{cell:"'Policy'!E6",...binding}}});for(const value of [7,7.0,7.5])hand593(p,{"'Policy'!E6":value},{result:'#N/A'});}
  }
});
test('FED593 str containers decline on active paths but inactive unsupported branches are lazy',()=>{
  for(const optimize of [true,false]){
    for(const value of ['[10,20,30]','[]','{}','{"v":7}'])hand593(emitExcel(compileModel(`func run() -> String:\n\treturn str(${value})\n`,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},{result:'#N/A'});
    const lit='func run() -> Array:\n\treturn [str([1]) if false else "safe",false and str({})=="x",true or str(0.1)=="x",str(null) if true else str([1])]\n';hand593(emitExcel(compileModel(lit,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array593(['safe',false,true,'<null>']));
    for(const value of ['[1]','{}','0.1','log(-1.0)']){const p=emitExcel(compileModel(`func run(flag: bool) -> String:\n\treturn str(${value}) if flag else "safe"\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand593(p,{"'Policy'!E6":false},{result:'safe'});hand593(p,{"'Policy'!E6":true},{result:'#N/A'});}
  }
});
test('FED593 str dynamic Boolean String NIL avoids spreadsheet General format and case coercion',()=>{
  for(const optimize of [true,false]){
    const p=emitExcel(compileModel('func run(v: Variant) -> String:\n\treturn str(v)\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{v:{cell:"'Policy'!E6",type:'variant'}}});
    const formulas=[...Object.values(p.formulas),...Object.values(p.outputs)].join('\n');assert.doesNotMatch(formulas,/&""|\bTEXT\(/,'no spreadsheet General/locale formatting');assert.match(formulas,/"true","false"/,'Boolean text uses explicit lowercase source spellings');assert.match(formulas,/"<null>"/,'NIL uses explicit source spelling');
    for(const [value,expected]of [[true,'true'],[false,'false'],[null,'<null>'],['MiXeD','MiXeD'],['TRUE','TRUE'],['FaLsE','FaLsE'],['',''],['7.0','7.0'],[new CellError('#REF!'),'#N/A']])hand593(p,{"'Policy'!E6":value},{result:expected});
    for(const [kind,source,valid,invalid]of [['boolean','bool',true,7],['string','String','MiXeD',true]]){const q=emitExcel(compileModel(`func run(v: ${source}) -> String:\n\treturn str(v)\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{v:{cell:"'Policy'!E6",type:kind}}});hand593(q,{"'Policy'!E6":valid},{result:kind==='boolean'?'true':'MiXeD'});hand593(q,{"'Policy'!E6":invalid},{result:'#N/A'});hand593(q,{"'Policy'!E6":new CellError('#VALUE!')},{result:'#N/A'});}
  }
});
test('FED593 str optional NIL absent defaults active errors and inactive values stay distinct',()=>{
  for(const optimize of [true,false]){
    const p=emitExcel(compileModel('func run(d: Dictionary) -> Array:\n\treturn [str(d.get("v")),str(d.get("v","default"))]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{v:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{cell:"'Policy'!E7",type:'variant'}}}}});
    for(const value of [new CellError('#REF!'),7,null])hand593(p,{"'Policy'!E6":false,"'Policy'!E7":value},array593(['<null>','default']));
    hand593(p,{"'Policy'!E6":true,"'Policy'!E7":null},array593(['<null>','<null>']));hand593(p,{"'Policy'!E6":true,"'Policy'!E7":new CellError('#REF!')},array593(['#N/A','#N/A']));
    for(const invalid of [0,3,null,'',new CellError('#REF!')])hand593(p,{"'Policy'!E6":invalid,"'Policy'!E7":'x'},array593(['#N/A','#N/A']));
    const q=emitExcel(compileModel('func run(flag: bool,v: Variant) -> String:\n\treturn str(v) if flag else "safe"\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'},v:{cell:"'Policy'!E7",type:'variant'}}});for(const value of [7,new CellError('#REF!')]){hand593(q,{"'Policy'!E6":false,"'Policy'!E7":value},{result:'safe'});hand593(q,{"'Policy'!E6":true,"'Policy'!E7":value},{result:'#N/A'});}
  }
});
test('FED593 str NIL produces an owned String without changing unavailable direct NIL output',()=>{
  for(const optimize of [true,false]){
    const p=emitExcel(compileModel('func run() -> Array:\n\tvar a := [null]\n\ta.resize(2)\n\treturn [str(a[0]),str(a.get(-1)),typeof(str(null)),str(null)=="<null>",null]\n',{entrypoints:['run']}),{entrypoint:'run',optimize});hand593(p,{},array593(['<null>','<null>',4,true,'#N/A']));
    const bad=emitExcel(compileModel('func run() -> String:\n\treturn str({}.missing)\n',{entrypoints:['run']}),{entrypoint:'run',optimize});hand593(bad,{},{result:'#N/A'});
  }
});
test('FED593 str runtime choices and earlier unavailable access cannot be sanitized',()=>{
  const source='func run(flag: bool,v: Variant) -> Array:\n\treturn [str(7 if flag else 7.0),str(null if flag else v),str(flag),str("ABC" if flag else "def"),str(v==null)]\n';
  for(const optimize of [true,false]){
    const p=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'},v:{cell:"'Policy'!E7",type:'variant'}}});
    for(const flag of [true,false])hand593(p,{"'Policy'!E6":flag,"'Policy'!E7":'MiXeD'},array593(flag?['7','<null>','true','ABC','false']:['7.0','MiXeD','false','def','false']));
    const q=emitExcel(compileModel('func run(flag: bool) -> String:\n\tvar d := {} if flag else {"v":null}\n\treturn str(d.v)\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand593(q,{"'Policy'!E6":false},{result:'<null>'});hand593(q,{"'Policy'!E6":true},{result:'#N/A'});
  }
});
// END FED593 additions.

// BEGIN FED591 additions; all prior84 groups remain byte-identical below.
const hand591=(p,values,expected)=>{const got=evaluate(p,values,{coerceBlankSelections:true});for(const [key,value]of Object.entries(expected))assert.equal(got.output(key),value,key);};
const array591=expected=>Object.fromEntries(expected.map((v,i)=>[`result[${i}]`,v]));
test('FED591 branch-order every observer copy and merge refuses invented union order',()=>{
  const pre='func run(flag: bool) -> Array:\n\tvar d := {}\n\tif flag:\n\t\td["2"] = "two"\n\t\td["1"] = "one"\n\telse:\n\t\td["1"] = "one"\n\t\td["2"] = "two"\n',loop='\tvar out := []\n\tfor k in d:\n\t\tout.append(k)\n\treturn out\n';
  for(const optimize of [true,false]){
    for(const tail of [loop,'\treturn d.keys()\n','\treturn d.values()\n','\td = d.duplicate(true)\n'+loop,'\tvar e := {}\n\te.merge(d,true)\n\td = e\n'+loop,'\tvar e := {}\n\te.merge(d.duplicate(true),true)\n\td = e\n'+loop])assert.throws(()=>emitExcel(compileModel(pre+tail,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}}),/order.*unproved|unproved.*order/);
    const reinsert='func run(flag: bool) -> Array:\n\tvar d := {}\n\tif flag:\n\t\td["2"] = "two"\n\td["1"] = "one"\n';
    for(const insertion of ['\td["2"] = "two"\n','\td.merge({"2":"two"},true)\n'])assert.throws(()=>emitExcel(compileModel(reinsert+insertion+loop,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}}),/order.*unproved|unproved.*order/);
    const good=emitExcel(compileModel('func run(flag: bool) -> Array:\n\tvar d := {"2":"two","1":"one"} if flag else {"1":"one","2":"two"}\n\tvar out := []\n\tfor k in d:\n\t\tout.append(k)\n\treturn out\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});for(const flag of [true,false])hand591(good,{"'Policy'!E6":flag},array591(flag?['2','1']:['1','2']));
  }
});
test('FED591 external-reinput rereads own properties and constants cannot retain mutable proofs',()=>{
  const make=compileModel('func run() -> Dictionary:\n\treturn {"a":"A","b":"B","nested":{"a":"A","b":"B"}}\n',{entrypoints:['run']}),keys=compileModel('func run(d: Dictionary) -> Array:\n\treturn d.keys()\n',{entrypoints:['run']}),nested=compileModel('func run(d: Dictionary) -> Array:\n\treturn d.nested.keys()\n',{entrypoints:['run']});
  for(const optimize of [true,false])for(const preserveNumericTypes of [true,false]){const d=evaluateModel(make,'run',[],{preserveNumericTypes});delete d.a;d.a='A';delete d.nested.a;d.nested.a='A';hand591(emitExcel(keys,{entrypoint:'run',optimize,arguments:{d}}),{},array591(['b','nested','a']));hand591(emitExcel(nested,{entrypoint:'run',optimize,arguments:{d}}),{},array591(['b','a']));}
  const d=evaluateModel(compileModel('func run() -> Dictionary:\n\treturn {"2":"two","1":"one"}\n',{entrypoints:['run']}),'run');for(const optimize of [true,false])assert.throws(()=>emitExcel(keys,{entrypoint:'run',optimize,arguments:{d}}),/external.*order|order.*external/);
  for(const optimize of [true,false])hand591(emitExcel(compileModel('const D = {"2":"two","1":"one"}\nfunc run() -> Array:\n\treturn D.keys()\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array591(['2','1']));
});
test('FED591 logical-resize uses prior length not retained capacity in both modes',()=>{
  for(const optimize of [true,false]){
    for(const mutation of ['alias.pop_back()','alias.resize(1)'])for(const innerGrow of [true,false]){const s='func run(flag: bool) -> Array:\n\tvar a := [1,7]\n\tvar alias := a\n\tif flag:\n\t\t'+mutation+'\n'+(innerGrow?'\t\talias.resize(2)\n':'\ta.resize(2)\n')+'\treturn [typeof(a[1]),a[1]==null,9 if a[1]==null else a[1]]\n',p=emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});for(const flag of [true,false])hand591(p,{"'Policy'!E6":flag},array591(flag?[0,true,9]:[2,false,7]));}
    const p=emitExcel(compileModel('func run(p: bool,q: bool) -> Array:\n\tvar a := [1,7]\n\tif p:\n\t\ta.pop_back()\n\tif q:\n\t\ta.resize(2)\n\treturn [a.size(),typeof(a[-1]),a[-1]==null]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{p:{cell:"'Policy'!E6",type:'boolean'},q:{cell:"'Policy'!E7",type:'boolean'}}});for(const x of [true,false])for(const y of [true,false])hand591(p,{"'Policy'!E6":x,"'Policy'!E7":y},array591([x&&!y?1:2,x&&y?0:2,x&&y]));
    const e=emitExcel(compileModel('func run(flag: bool) -> Array:\n\tvar a := []\n\tif flag:\n\t\ta.append(7)\n\ta.pop_back()\n\ta.resize(1)\n\treturn [typeof(a[0]),a[0]==null]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});hand591(e,{"'Policy'!E6":true},array591([0,true]));hand591(e,{"'Policy'!E6":false},array591(['#N/A','#N/A']));
  }
});
test('FED591 membership-receiver cannot inspect numeric wrappers in either mode',()=>{
  for(const optimize of [true,false]){
    for(const receiver of ['7','7.0','true','null'])for(const op of ['in','not in'])for(const key of ['value','numericType'])assert.throws(()=>emitExcel(compileModel(`func run() -> bool:\n\treturn "${key}" ${op} ${receiver}\n`,{entrypoints:['run']}),{entrypoint:'run',optimize}),e=>e.name==='ModelCompileError'&&/membership.*receiver|receiver.*membership/.test(e.message));
    assert.throws(()=>emitExcel(compileModel('func run() -> bool:\n\treturn 1 in "1"\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),/String.*membership|membership.*String/);
    hand591(emitExcel(compileModel('func run() -> Array:\n\treturn ["Tag" in "Taggy","tag" in "Taggy","X" not in "Taggy","__proto__" in {"__proto__":7},7 in [7.0],7 not in [7.0]]\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array591([true,false,true,true,false,true]));
    hand591(emitExcel(compileModel('func run() -> int:\n\tif false:\n\t\tvar unused = "value" in 7\n\treturn 9\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),{}, {result:9});
  }
});
// END FED591 additions.

// BEGIN FED590 additions; prior70 groups below remain byte-identical.
const hand590=(p,values,expected)=>{const got=evaluate(p,values,{coerceBlankSelections:true});for(const [key,value]of Object.entries(expected))assert.equal(got.output(key),value,key);};
const array590=expected=>Object.fromEntries(expected.map((v,i)=>[`result[${i}]`,v]));
test('FED590 4369440164 shared Variant-sensitive has in not-in in both modes',()=>{
  for(const optimize of [true,false]){
    const p=emitExcel(compileModel('func run() -> Array:\n\treturn [7 in [7.0],7 not in [7.0],7 in [7],7.0 in [7.0],true in [1],null in [null],"Tag" in ["tag"],7==7.0]\n',{entrypoints:['run']}),{entrypoint:'run',optimize});hand590(p,{},array590([false,true,true,true,false,true,false,true]));
    for(const numericType of ['int','float']){const p=emitExcel(compileModel('func run(v: Variant) -> Array:\n\treturn [[7].has(v),v in [7],v not in [7]]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{v:{cell:"'Policy'!E6",type:'variant',numericType}}});for(const [v,hand]of [[7,numericType==='int'?[true,true,false]:[false,false,true]],[true,[false,false,true]],[null,[false,false,true]]])hand590(p,{"'Policy'!E6":v},array590(hand));}
    const q=emitExcel(compileModel('func run(flag: bool) -> Array:\n\tvar a := [1]\n\tif flag:\n\t\ta.append(7.0)\n\treturn [7 in a,7.0 in a,7.0 not in a]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});for(const flag of [true,false])hand590(q,{"'Policy'!E6":flag},array590([false,flag,!flag]));
    assert.throws(()=>emitExcel(compileModel('func run() -> bool:\n\treturn [1] in [[1]]\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),/membership.*scalar|scalar.*membership/);
  }
});
test('FED590 4369440168 ordered String keys updates merge copies and for in both modes',()=>{
  const s='func run() -> Array:\n\tvar d := {"2":"a","1":"b","01":"c","4294967294":"d","4294967295":"e","__proto__":"p","constructor":"k","toString":"t"}\n\tvar alias := d\n\talias["1"] = "B"\n\td.merge({"2":"wrong","new":"n","01":"wrong"},false)\n\tvar shallow := d.duplicate(false)\n\tvar deep := d.duplicate(true)\n\tdeep["1"] = "deep"\n\tshallow["tail"] = "s"\n\tvar visits := []\n\tfor k in d:\n\t\tvisits.append(k)\n\treturn [d.keys(),d.values(),visits,shallow.keys(),deep.keys(),d["1"],deep["1"]]\n',keys=['2','1','01','4294967294','4294967295','__proto__','constructor','toString','new'];
  for(const optimize of [true,false]){const p=emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize}),expected={};[keys,['a','B','c','d','e','p','k','t','n'],keys,keys.concat('tail'),keys].forEach((a,i)=>a.forEach((v,j)=>expected[`result[${i}][${j}]`]=v));Object.assign(expected,{'result[5]':'B','result[6]':'deep'});hand590(p,{},expected);}
});
test('FED590 4369440169 null literal dynamic negative get resize and defaults in both modes',()=>{
  const s='func run() -> Array:\n\tvar a := [null,7,null]\n\ta.resize(4)\n\tvar d := {"v":null}\n\treturn [typeof(a[0]),a[0]==null,typeof(a[-1]),a.get(-1)==null,a.get(-3)==7,typeof(a.get(0)),a.get(0)==null,typeof(d.get("v",9)),d.get("v",9)==null,d.get("missing",9),d.get("missing",null)==null]\n';
  for(const optimize of [true,false]){
    hand590(emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array590([0,true,0,true,true,0,true,0,true,9,true]));
    const p=emitExcel(compileModel('func run(i: int) -> Array:\n\tvar a := [null,7]\n\tvar v = a[i]\n\tvar g = a.get(i)\n\treturn [typeof(v),v==null,typeof(g),g==null,9 if v==null else v]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{i:{cell:"'Policy'!E6",type:'number',numericType:'int'}}});for(const i of [0,-2,1,-1])hand590(p,{"'Policy'!E6":i},array590([i===0||i===-2?0:2,i===0||i===-2,i===0||i===-2?0:2,i===0||i===-2,i===0||i===-2?9:7]));
    hand590(p,{"'Policy'!E6":3},array590(['#N/A','#N/A','#N/A','#N/A','#N/A']));
    const raw=emitExcel(compileModel('func run() -> Variant:\n\treturn [null][0]\n',{entrypoints:['run']}),{entrypoint:'run',optimize});hand590(raw,{}, {result:'#N/A'});
    assert.throws(()=>emitExcel(compileModel('func run() -> Variant:\n\treturn [null].get(0,9)\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),/get.*argument|argument.*get/);
  }
});
test('FED590 4369440171 empty live Array and Dictionary Boolean contexts both modes',()=>{
  for(const optimize of [true,false]){
    const p=emitExcel(compileModel('func run() -> Array:\n\treturn [not [],not {},1 if [] else 2,1 if {} else 2,[] and log(-1.0)>0,[1] or log(-1.0)>0,{} or false,{"v":null} and true]\n',{entrypoints:['run']}),{entrypoint:'run',optimize});hand590(p,{},array590([true,true,2,2,false,true,false,true]));
    const s='func run(flag: bool) -> Array:\n\tvar a := []\n\tvar alias := a\n\tvar before = not a\n\tif flag:\n\t\talias.append(null)\n\tvar middle = not a\n\tif flag:\n\t\talias.pop_back()\n\tvar d := {}\n\tvar other := d\n\tvar empty = not d\n\tother.merge({"v":null},true)\n\treturn [before,middle,not a,empty,not d,1 if d else 2,a and true,a or false]\n',q=emitExcel(compileModel(s,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});for(const flag of [true,false])hand590(q,{"'Policy'!E6":flag},array590([true,!flag,true,true,false,1,false,false]));
    const d=emitExcel(compileModel('func run(flag: bool) -> Array:\n\tvar d := {}\n\tif flag:\n\t\td["v"] = null\n\treturn [not d,1 if d else 2,d and true,d or false]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});for(const flag of [true,false])hand590(d,{"'Policy'!E6":flag},array590([!flag,flag?1:2,flag,flag]));
  }
});
test('FED590 source constants preserve numeric-looking key order across module boundaries',()=>{
  for(const optimize of [true,false]){const p=emitExcel(compileModel('const D = {"2":"first","1":"second","01":"third"}\nfunc run() -> Array:\n\treturn [D.keys(),D.values()]\n',{entrypoints:['run']}),{entrypoint:'run',optimize});hand590(p,{}, {'result[0][0]':'2','result[0][1]':'1','result[0][2]':'01','result[1][0]':'first','result[1][1]':'second','result[1][2]':'third'});}
});
test('FED590 external numeric-looking input order refuses observation and preserves lookup',()=>{
  const d=JSON.parse('{"2":"first","1":"second","01":"third"}');
  for(const optimize of [true,false]){
    for(const action of ['return d.keys()','return d.values()','var out := []\n\tfor k in d:\n\t\tout.append(k)\n\treturn out','var c := d.duplicate(true)\n\treturn c.keys()'])assert.throws(()=>emitExcel(compileModel('func run(d: Dictionary) -> Variant:\n\t'+action+'\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d}}),/external.*order|order.*external/);
    hand590(emitExcel(compileModel('func run(d: Dictionary) -> Array:\n\treturn [d["2"],d["1"],d.has("01"),not d]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d}}),{},array590(['first','second',true,false]));
  }
});
test('FED590 optional Dictionary truth uses active presence not capacity or null values',()=>{
  for(const optimize of [true,false]){
    const p=emitExcel(compileModel('func run(d: Dictionary) -> Array:\n\treturn [not d,1 if d else 2,d and true,d or false]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{v:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:null}}}});for(const flag of [true,false])hand590(p,{"'Policy'!E6":flag},array590([!flag,flag?1:2,flag,flag]));for(const bad of [0,3,null,new CellError('#REF!')])hand590(p,{"'Policy'!E6":bad},array590(['#N/A','#N/A','#N/A','#N/A']));
    hand590(emitExcel(compileModel('func run() -> Array:\n\tvar a := [null]\n\tvar d := {"v":null}\n\treturn [not a,not a[0],not d,not d.v,d.get("v",true)==null,d.get("missing",true)]\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),{},array590([false,true,false,true,true,true]));
  }
});
// END FED590 additions.

test('FED586 optional presence is strictly Boolean under enclosing parent guards',()=>{
  const presence={cell:"'Policy'!E6",type:'boolean'},leaf={cell:"'Policy'!E7",type:'number',numericType:'int'},child={cell:"'Policy'!E8",type:'boolean'},invalid=[0,3,null,'','TRUE','text',new CellError('#REF!')];
  for(const optimize of [true,false]){
    for(const source of ['func run(d: Dictionary) -> Variant:\n\treturn d.has("v")\n','func run(d: Dictionary) -> Array:\n\treturn [d.has("v"),typeof(d.has("v"))]\n']){const p=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{v:{$optional:true,present:presence,value:leaf}}}}),paths=Object.keys(p.outputs);
      for(const bad of invalid){const got=evaluate(p,{"'Policy'!E6":bad,"'Policy'!E7":7});for(const path of paths)assert.equal(got.output(path),'#N/A',`presence ${String(bad)}, ${optimize}`);}
      for(const present of [true,false]){const got=evaluate(p,{"'Policy'!E6":present,"'Policy'!E7":7});assert.equal(got.output(paths[0]),present);assert.equal(typeof got.output(paths[0]),'boolean');if(paths.length===2)assert.equal(got.output(paths[1]),1);}
    }
    const nested=emitExcel(compileModel('func run(d: Dictionary) -> Variant:\n\treturn d.has("inner")\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{inner:{$optional:true,present:presence,value:{v:{$optional:true,present:child,value:leaf}}}}}});
    for(const bad of invalid){assert.equal(evaluate(nested,{"'Policy'!E6":false,"'Policy'!E8":bad,"'Policy'!E7":new CellError('#N/A')}).output('result'),false,'inactive nested invalid presence/value cannot poison parent');assert.equal(evaluate(nested,{"'Policy'!E6":true,"'Policy'!E8":bad,"'Policy'!E7":7}).output('result'),'#N/A');assert.equal(evaluate(nested,{"'Policy'!E6":bad,"'Policy'!E8":false,"'Policy'!E7":7}).output('result'),'#N/A');}
    const shared=emitExcel(compileModel('func run(d: Dictionary) -> Array:\n\treturn [d.has("a"),d.has("b")]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:Object.fromEntries([['a',presence],['b',{cell:"'Policy'!E9",type:'boolean'}]].map(([key,parent])=>[key,{$optional:true,present:parent,value:{v:{$optional:true,present:child,value:leaf}}}]))}});
    for(const a of [true,false])for(const b of [true,false]){const got=evaluate(shared,{"'Policy'!E6":a,"'Policy'!E9":b,"'Policy'!E8":3,"'Policy'!E7":7});for(let i=0;i<2;i++)assert.equal(got.output(`result[${i}]`),a||b?'#N/A':false,'guard-specific CSE must retain each active parent validation');}
  }
});
test('FED586 own String keys survive root output maps copies merges and packing',()=>{
  const root='func run() -> Dictionary:\n\treturn {"__proto__":"kept","constructor":"ctor","toString":"text","safe":"yes"}\n',hand=JSON.parse('{"__proto__":"kept","constructor":"ctor","toString":"text","safe":"yes"}');
  for(const optimize of [true,false]){
    const p=emitExcel(compileModel(root,{entrypoints:['run']}),{entrypoint:'run',optimize}),got=evaluate(p);assert.deepEqual(Object.keys(p.outputs).sort(),Object.keys(hand).sort());
    for(const [key,value]of Object.entries(hand)){assert.equal(Object.hasOwn(p.outputs,key),true);assert.equal(Object.hasOwn(p.outputPresence,key),true);assert.equal(got.output(key),value);assert.equal(Object.getPrototypeOf(p.outputs),Object.prototype);}
    const arithmetic='func run(x: float) -> Dictionary:\n\treturn {"__proto__":x*2.0,"constructor":x+1.0,"toString":x-1.0}\n',outputs=Object.fromEntries(['__proto__','constructor','toString'].map((k,i)=>[k,`'Economy'!E${20+i}`])),q=emitExcel(compileModel(arithmetic,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'number',numericType:'float'}},outputs});
    for(const x of [-2,0,3.5]){const actual=evaluate(q,{"'Policy'!E6":x});for(const [key,value]of [['__proto__',x*2],['constructor',x+1],['toString',x-1]]){assert.equal(actual.output(key),value);assert.equal(Object.hasOwn(q.outputNumericTypes,key),true);assert.equal(q.outputNumericTypes[key],'float');assert.equal(q.formulas[outputs[key]],q.outputs[key]);}}
    const copy='func run() -> Array:\n\tvar a := [1]\n\tvar d := {"__proto__":a,"constructor":a,"toString":a}\n\tvar deep := d.duplicate(true)\n\tvar shallow := d.duplicate(false)\n\ta[0] = 9\n\tdeep["__proto__"][0] = 7\n\tvar merged := {}\n\tmerged.merge(deep,true)\n\treturn [merged.size(),merged.has("__proto__"),merged["constructor"][0],merged["toString"][0],shallow["__proto__"][0],deep["__proto__"][0]/2,typeof(deep["__proto__"][0])]\n',c=emitExcel(compileModel(copy,{entrypoints:['run']}),{entrypoint:'run',optimize}),cg=evaluate(c);[3,true,7,7,9,3,2].forEach((v,i)=>assert.equal(cg.output(`result[${i}]`),v));
    const input=emitExcel(compileModel('func run(d: Dictionary) -> Dictionary:\n\tvar out := {}\n\tout.merge(d.duplicate(true),true)\n\treturn out\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:hand}}),ig=evaluate(input);for(const [key,value]of Object.entries(hand))assert.equal(ig.output(key),value);
    const optional=emitExcel(compileModel('func run(d: Dictionary) -> Dictionary:\n\treturn d\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:Object.fromEntries([['__proto__',{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:'kept'}]])}});assert.equal(Object.hasOwn(optional.outputs,'__proto__'),true);for(const [present,expected]of [[true,'kept'],[false,'#N/A'],[3,'#N/A']])assert.equal(evaluate(optional,{"'Policy'!E6":present}).output('__proto__'),expected);
    const symbols=emitExcel(compileModel('const __proto__: int = 5\nfunc constructor(__proto__: int) -> int:\n\tvar toString := __proto__\n\tif toString > 0:\n\t\ttoString += 2\n\treturn toString\nfunc run() -> Array:\n\tvar __proto__ := constructor(__proto__)\n\treturn [__proto__,typeof(__proto__)]\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),sg=evaluate(symbols);assert.equal(sg.output('result[0]'),7);assert.equal(sg.output('result[1]'),2);
  }
});
test('FED586 method receiver and source kinds fail closed in both formula modes',()=>{
  const bad=['return "abc".has("length")','return "abc".get("length",0)','return "abc".size()','return "abc".keys()','return "abc".duplicate()', 'var d := {}\n\td.merge([7],true)\n\treturn [d.size(),d.get("0",0)]','var d := {}\n\td.merge(null,true)\n\treturn d','var d := {}\n\td.merge("text",true)\n\treturn d','var a := []\n\ta.merge({"v":7},true)\n\treturn a','var a := [1]\n\ta.append_array({"v":7})\n\treturn a','return {}.is_valid_float()'];
  for(const optimize of [true,false]){
    for(const body of bad){let p;try{p=emitExcel(compileModel('func run() -> Variant:\n\t'+body+'\n',{entrypoints:['run']}),{entrypoint:'run',optimize});}catch(e){assert.equal(e.name,'ModelCompileError');continue;}assert.ok(p.diagnostics.some(d=>d.kind==='unavailable-guard'));const got=evaluate(p);for(const path of Object.keys(p.outputs))assert.equal(got.output(path),'#N/A',body);}
    for(const method of ['"abc".has("length")','d.merge([7],true)']){const p=emitExcel(compileModel(`func run(flag: bool) -> int:\n\tvar d := {}\n\tif flag:\n\t\t${method}\n\treturn 9\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});assert.equal(evaluate(p,{"'Policy'!E6":false}).output('result'),9);assert.equal(evaluate(p,{"'Policy'!E6":true}).output('result'),'#N/A');}
  }
});
test('PR120 4369307575 Array.has is Variant-type-sensitive scalar value membership',()=>{
  const source='func run() -> Array:\n\tvar a := [10,20,7,true,"Tag",null]\n\treturn [a.has(0),a.has(20),a.has(7),a.has(7.0),[7.0].has(7),[7.0].has(7.0),a.has(true),a.has(false),a.has("Tag"),a.has("tag"),a.has(null),[].has(0),7==7.0]\n',hand=[false,true,true,false,false,true,true,false,true,false,true,false,true];
  for(const optimize of [true,false]){
    const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize}),got=evaluate(program);hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v,`membership ${i}, ${optimize}`));
    const dynamic='func run(x: Variant) -> Array:\n\treturn [[7].has(x),[7.0].has(x),[true].has(x),["Tag"].has(x),[null].has(x)]\n';
    for(const numericType of ['int','float']){const p=emitExcel(compileModel(dynamic,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'variant',numericType}}});
      for(const [x,expected]of [[7,[numericType==='int',numericType==='float',false,false,false]],[true,[false,false,true,false,false]],['Tag',[false,false,false,true,false]],['tag',[false,false,false,false,false]],[null,[false,false,false,false,true]]]){const actual=evaluate(p,{"'Policy'!E6":x},{coerceBlankSelections:true});expected.forEach((v,i)=>assert.equal(actual.output(`result[${i}]`),v));}}
    assert.throws(()=>emitExcel(compileModel('func run() -> bool:\n\treturn [[1]].has([1])\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),/membership.*scalar|scalar.*membership/);
    const guarded=emitExcel(compileModel('func run(flag: bool) -> Array:\n\tvar a := [7 if flag else 7.0]\n\tvar b := [1]\n\tif flag:\n\t\tb.append(20)\n\treturn [a.has(7),a.has(7.0),b.has(20),b.has(0)]\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{flag:{cell:"'Policy'!E6",type:'boolean'}}});
    for(const [flag,hand]of [[true,[true,false,true,false]],[false,[false,true,false,false]]]){const actual=evaluate(guarded,{"'Policy'!E6":flag});hand.forEach((v,i)=>assert.equal(actual.output(`result[${i}]`),v));}
  }
});
test('PR120 4369307577 absent optional integer validation is guarded by presence',()=>{
  const sources=['func run(d: Dictionary) -> bool:\n\treturn d.has("v")\n','func run(d: Dictionary) -> bool:\n\treturn d.inner.has("v")\n'];
  for(const optimize of [true,false])for(const [i,source]of sources.entries()){
    const optional={$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{cell:"'Policy'!E7",type:'number',numericType:'int'}},arguments_={d:i?{inner:{$optional:true,present:{cell:"'Policy'!E8",type:'boolean'},value:{v:optional}}}:{v:optional}};
    const p=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:arguments_});
    for(const value of [null,'unused',true,1.5,7])assert.equal(evaluate(p,{"'Policy'!E6":false,"'Policy'!E7":value,"'Policy'!E8":true}).output('result'),false,`absent ${value}, ${optimize}`);
    assert.equal(evaluate(p,{"'Policy'!E6":true,"'Policy'!E7":7,"'Policy'!E8":true}).output('result'),true);
    for(const value of [null,'unused',true,1.5])assert.equal(evaluate(p,{"'Policy'!E6":true,"'Policy'!E7":value,"'Policy'!E8":true}).output('result'),'#N/A');
  }
  for(const optimize of [true,false]){const p=emitExcel(compileModel('func run(d: Dictionary) -> bool:\n\treturn d.has("inner")\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{inner:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{v:{$optional:true,present:{cell:"'Policy'!E8",type:'boolean'},value:{cell:"'Policy'!E7",type:'number',numericType:'int'}}}}}}});assert.equal(evaluate(p,{"'Policy'!E6":false,"'Policy'!E7":'unused',"'Policy'!E8":true}).output('result'),false);}
});
test('PR120 4369307578 array iteration reads live later values with structural refusal',()=>{
  const source='func change(a: Array,x: bool) -> void:\n\tif x:\n\t\ta[1] = 9\nfunc run(x: bool) -> Array:\n\tvar a := [1,2]\n\tvar alias := a\n\tvar out := []\n\tfor item in a:\n\t\tout.append(item)\n\t\tchange(alias,x)\n\treturn out\n';
  for(const optimize of [true,false]){const p=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'boolean'}}});for(const [x,hand]of [[true,[1,9]],[false,[1,2]]]){const got=evaluate(p,{"'Policy'!E6":x});hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));}
    for(const mutation of ['a.append(3)','a.pop_back()','a.append(3)\n\t\ta.pop_back()'])assert.throws(()=>emitExcel(compileModel(`func run() -> Array:\n\tvar a := [1,2]\n\tfor item in a:\n\t\t${mutation}\n\treturn a\n`,{entrypoints:['run']}),{entrypoint:'run',optimize}),/iterable.*mutat|iterable.*resiz/);
  }
});
test('PR120 4369307581 hex prefixes precede decimal exponent provenance',()=>{
  for(const optimize of [true,false]){const p=emitExcel(compileModel('func run() -> Array:\n\treturn [typeof(0xEF),0xEF/2]\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),got=evaluate(p);assert.equal(got.output('result[0]'),2);assert.equal(got.output('result[1]'),119);
    const source='func run() -> Array:\n\treturn [typeof(0xef),0xef/2,typeof(0xE_F),0xE_F/2,typeof(1_000),1_000/2,typeof(1e2),1e2/2,typeof(1_0e1),1_0e1/2,typeof(1.0e-1),1.0e-1/2]\n',q=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize}),actual=evaluate(q);[2,119,2,119,2,500,3,50,3,50,3,.05].forEach((v,i)=>assert.equal(actual.output(`result[${i}]`),v));}
});
test('PR120 4369307584 non-String dictionary keys refuse throughout literal access mutation methods merge',()=>{
  const bodies=['var d := {1:"number","1":"text"}\n\treturn [d.size(),d[1],d["1"]]', 'var d := {"1":7}\n\treturn d[1]', 'var d := {"1":7}\n\td[1] = 8\n\treturn d', 'return {"1":7}.has(1)', 'return {"1":7}.get(1,9)', 'var d := {}\n\td.merge({1:7},true)\n\treturn d','return 1 in {"1":7}'];
  for(const optimize of [true,false]){
    for(const body of bodies)assert.throws(()=>emitExcel(compileModel('func run() -> Variant:\n\t'+body+'\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),/dictionary.*String|String.*dictionary/,body);
    for(const expression of ['d[x]','d.has(x)','d.get(x,9)']){const p=emitExcel(compileModel(`func run(x: Variant) -> Variant:\n\tvar d := {"1":7}\n\treturn ${expression}\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'variant',numericType:'int'}}});assert.equal(evaluate(p,{"'Policy'!E6":'1'}).output('result'),expression==='d.has(x)'?true:7);for(const x of [1,true,null])assert.equal(evaluate(p,{"'Policy'!E6":x}).output('result'),'#N/A');}
    const p=emitExcel(compileModel('func run() -> Array:\n\tvar d := {"1":7}\n\td["1"] = 8\n\td.merge({"s":9},true)\n\treturn [d["1"],d.has("s"),d.get("missing",3)]\n',{entrypoints:['run']}),{entrypoint:'run',optimize});[8,true,3].forEach((v,i)=>assert.equal(evaluate(p).output(`result[${i}]`),v));
  }
});
test('same-category optional float phis retain actual category for Boolean text and blank edits',()=>{
  const source='func run(d: Dictionary) -> Dictionary:\n\tif not d.has("v") or typeof(d.v) != TYPE_FLOAT:\n\t\treturn {"ok":false}\n\treturn {"ok":true,"v":d.v/2,"type":typeof(d.v)}\n';
  for(const optimize of [true,false]){const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{v:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{cell:"'Policy'!E7",type:'number',numericType:'float'}}}}});
    for(const coerceBlankSelections of [true,false])for(const present of [true,false])for(const x of [5.0,0,true,false,'5','wrong','',null]){const got=evaluate(program,{"'Policy'!E6":present,"'Policy'!E7":x},{coerceBlankSelections}),valid=present&&typeof x==='number';assert.equal(got.output('ok'),valid,`float edit ${x}, present=${present}, optimize=${optimize}`);assert.equal(got.output('v'),valid?x/2:'#N/A');assert.equal(got.output('type'),valid?3:'#N/A');}
  }
});
test('same-category Boolean and String defaults do not certify mutable cell categories',()=>{
  for(const optimize of [true,false])for(const [type,defaultText,defaultValue,typeEnum,validValues]of [['boolean','false',false,'TYPE_BOOL',[true,false]],['string','"fallback"','fallback','TYPE_STRING',['text','']]]){
    const source=`func run(d: Dictionary) -> Dictionary:\n\tvar v = d.get("v",${defaultText})\n\tif typeof(v) != ${typeEnum}:\n\t\treturn {"ok":false}\n\treturn {"ok":true,"v":v}\n`,program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{v:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{cell:"'Policy'!E7",type}}}}});
    for(const present of [true,false])for(const x of [true,false,5,0,'text','',null]){const valid=!present||validValues.includes(x),got=evaluate(program,{"'Policy'!E6":present,"'Policy'!E7":x},{coerceBlankSelections:true});assert.equal(got.output('ok'),valid,`${type} ${x}/${present}`);assert.equal(got.output('v'),valid?(present?x:defaultValue):'#N/A');}
  }
});
test('nested same-category selections and CSE retain source categories independently of numeric values',()=>{
  const source='func run(d: Dictionary,x: bool,y: bool) -> Array:\n\tvar a = d.get("v",0.0)\n\tvar b = d.get("v",0.0)\n\tvar c = (a if x else b) if y else 1.0\n\treturn [typeof(a),typeof(b),typeof(c),c==true,c==1.0,c==null]\n';
  for(const optimize of [true,false]){const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{v:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{cell:"'Policy'!E7",type:'number',numericType:'float'}}},x:{cell:"'Policy'!E8",type:'boolean'},y:{cell:"'Policy'!E9",type:'boolean'}}});
    for(const present of [true,false])for(const x of [true,false])for(const y of [true,false])for(const [value,tag]of [[2,3],[true,1],['1',4],[null,0]]){const actualSource=present?value:0,sourceTag=present?tag:3,selected=y?actualSource:1;const hand=[sourceTag,sourceTag,y?sourceTag:3,selected===true,selected===1,selected===null],got=evaluate(program,{"'Policy'!E6":present,"'Policy'!E7":value,"'Policy'!E8":x,"'Policy'!E9":y},{coerceBlankSelections:true});hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v,`nested ${value}/${present}/${x}/${y}, mode=${optimize}`));}
    const raw=emitExcel(compileModel('func run(d: Dictionary) -> Variant:\n\treturn d.get("v",0.0)\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{v:{$optional:true,present:{cell:"\'Policy\'!E6",type:'boolean'},value:{cell:"\'Policy\'!E7",type:'number',numericType:'float'}}}}});assert.equal(evaluate(raw,{"\'Policy\'!E6":true,"\'Policy\'!E7":null},{coerceBlankSelections:true}).output('result'),'#N/A','source NIL must not materialize as healthy numeric zero');
  }
});
test('casts and truthiness consume source-category provenance; unproved text conversion is unavailable',()=>{
  const head='func run(d: Dictionary) -> Array:\n\tvar v = d.get("v",0.0)\n',cast=head+'\treturn [float(v),typeof(float(v)),int(v),typeof(int(v)),typeof(v)]\n',truth=head+'\treturn [not v,v and true,v or false]\n';
  for(const optimize of [true,false]){const binding={entrypoint:'run',optimize,arguments:{d:{v:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{cell:"'Policy'!E7",type:'number',numericType:'float'}}}}},program=emitExcel(compileModel(cast,{entrypoints:['run']}),binding),truthProgram=emitExcel(compileModel(truth,{entrypoints:['run']}),binding);
    for(const [value,hand]of [[5.5,[5.5,3,5,2,3]],[-5.5,[-5.5,3,-5,2,3]],[true,[1,3,1,2,1]],[false,[0,3,0,2,1]]]){const got=evaluate(program,{"'Policy'!E6":true,"'Policy'!E7":value});hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));}
    for(const value of ['5','invalid',null]){const got=evaluate(program,{"'Policy'!E6":true,"'Policy'!E7":value},{coerceBlankSelections:true});for(let i=0;i<5;i++)assert.equal(got.output(`result[${i}]`),'#N/A','closed cast refusal, no Excel text/blank coercion');}
    for(const value of [5,0,true,false,'text','',null]){const got=evaluate(truthProgram,{"'Policy'!E6":true,"'Policy'!E7":value},{coerceBlankSelections:true}),b=Boolean(value);[!b,b,b].forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));}
    const ordered=emitExcel(compileModel(head+'\treturn [v < INF,v > -INF]\n',{entrypoints:['run']}),binding);for(const value of [true,'5',null]){const got=evaluate(ordered,{"'Policy'!E6":true,"'Policy'!E7":value},{coerceBlankSelections:true});assert.equal(got.output('result[0]'),'#N/A');assert.equal(got.output('result[1]'),'#N/A');}
  }
});
test('optional Boolean has/typeof composition retains categories in both modes',()=>{
  const source='func run(d: Dictionary) -> Dictionary:\n\tif not d.has("b") or typeof(d.b) != TYPE_BOOL:\n\t\treturn {"ok":false}\n\treturn {"ok":true,"b":d.b}\n';
  const ir=compileModel(source,{entrypoints:['run']});
  for(const optimize of [true,false]){const program=emitExcel(ir,{entrypoint:'run',optimize,arguments:{d:{b:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{cell:"'Policy'!E7",type:'boolean'}}}}});
    for(const present of [true,false])for(const value of [true,false,5,'s',null]){const got=evaluate(program,{"'Policy'!E6":present,"'Policy'!E7":value}),valid=present&&typeof value==='boolean';assert.equal(got.output('ok'),valid);assert.equal(got.output('b'),valid?value:'#N/A');}
    const observed=source.replace('"b":d.b}', '"b":d.b,"type":typeof(d.b)}');
    assert.throws(()=>emitExcel(compileModel(observed,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{b:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{cell:"'Policy'!E7",type:'boolean'}}}}}),/cannot observe an unproved type enum/,'retained closed refusal: the current guard solver cannot discharge every unknown numeric edit alternative for a directly observed enum');
  }
});
test('heterogeneous scalar choices retain source typeof enums without coercion in both modes',()=>{
  for(const optimize of [true,false])for(const [yes,no,hand]of [['true','2.0',[[true,1,2],[2,3,2]]],['"text"','2.0',[["text",4,2],[2,3,2]]],['null','2.0',[["#N/A",0,2],[2,3,2]]]]){
    const source=`func run(x: bool) -> Array:\n\tvar v = ${yes} if x else ${no}\n\treturn [v,typeof(v),typeof(typeof(v))]\n`,program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'boolean'}}});
    for(const [i,x]of [true,false].entries()){const got=evaluate(program,{"'Policy'!E6":x});hand[i].forEach((v,j)=>assert.equal(got.output(`result[${j}]`),v,`${yes}/${no} ${x}, optimize=${optimize}`));}
  }
});
test('heterogeneous choices retain lazy numeric errors, explicit conversion and missing-value unavailability',()=>{
  const source='func run(x: bool) -> Array:\n\tvar v = true if x else 2.0\n\treturn [float(v)+1.0,7.0 if x else log(-1.0),log(-1.0) if x else 9.0,typeof(v)]\n';
  for(const optimize of [true,false]){const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'boolean'}}});
    for(const [x,hand]of [[true,[2,7,'#N/A',1]],[false,[3,'#N/A',9,3]]]){const got=evaluate(program,{"'Policy'!E6":x});hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));}
    assert.throws(()=>emitExcel(compileModel('func run(x: bool) -> Variant:\n\tvar v = true if x else 2.0\n\treturn v+1.0\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'boolean'}}}),/Boolean\/non-numeric/,'a reachable invalid Boolean arithmetic arm must not be coerced');
    const missing=emitExcel(compileModel('func run(d: Dictionary) -> int:\n\tvar unused = d.b\n\treturn 7\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{d:{b:{$optional:true,present:{cell:"'Policy'!E6",type:'boolean'},value:{cell:"'Policy'!E7",type:'boolean'}}}}});
    assert.equal(evaluate(missing,{"'Policy'!E6":true,"'Policy'!E7":false}).output('result'),7);assert.equal(evaluate(missing,{"'Policy'!E6":false,"'Policy'!E7":false}).output('result'),'#N/A');
  }
});
test('deep copies preserve heterogeneous scalar choices under nested guards in both modes',()=>{
  const source='func run(x: bool,y: bool) -> Array:\n\tvar a := [true if x else 2.0]\n\tvar b := ["text" if x else null]\n\tvar d := {"v":a if y else b}\n\tvar deep := d.duplicate(true)\n\ta[0] = "changed"\n\tb[0] = 9.0\n\treturn [deep.v[0],typeof(deep.v[0]),typeof(typeof(deep.v[0]))]\n';
  for(const optimize of [true,false]){const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'boolean'},y:{cell:"'Policy'!E7",type:'boolean'}}});
    for(const [x,y,hand]of [[true,true,[true,1,2]],[false,true,[2,3,2]],[true,false,['text',4,2]],[false,false,['#N/A',0,2]]]){const got=evaluate(program,{"'Policy'!E6":x,"'Policy'!E7":y});hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));}
  }
});
test('source typeof emits integer Variant enums and nested comparisons in both modes',()=>{
  const source='func run(x: Variant) -> Array:\n\treturn [typeof(x),typeof(typeof(x)),typeof(x)=="int",typeof(typeof(x))==TYPE_INT,typeof(null),typeof(true),typeof(5),typeof(5.0),typeof("x"),typeof({}),typeof([]),TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_DICTIONARY,TYPE_ARRAY,typeof(TYPE_FLOAT)]\n';
  const ir=compileModel(source,{entrypoints:['run']});
  for(const optimize of [true,false])for(const numericType of ['int','float']){const program=emitExcel(ir,{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'variant',numericType}}});
    for(const [x,tag]of [[5,numericType==='int'?2:3],[true,1],['x',4],[null,0]]){const got=evaluate(program,{"'Policy'!E6":x}),hand=[tag,2,false,true,0,1,2,3,4,27,28,0,1,2,3,4,27,28,2];hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v,`typeof ${x}, ${numericType}, optimize=${optimize}`));}
  }
});
test('typed constants emit coerced numeric values and integer typeof enums in both modes',()=>{
  const source='const A: float = 5\nconst B: int = -5.9\nconst C: float = B\nconst D = typeof(A)\nfunc run() -> Array:\n\treturn [A/2,typeof(A),B,C/2,typeof(C),D,typeof(D)]\n';
  for(const optimize of [true,false]){const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize}),got=evaluate(program);[2.5,3,-5,-2.5,3,3,2].forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));assert.equal(program.outputNumericTypes['result[0]'],'float');}
  assert.throws(()=>emitExcel(compileModel('const A: float = "5"\nfunc run() -> Variant:\n\treturn A\n',{entrypoints:['run']}),{entrypoint:'run'}),/typed float/);
});
test('lerpf integer inputs retain float signature in both modes',()=>{
  const source='func run(x: int) -> Array:\n\tvar a = lerpf(0,5,x)\n\treturn [a/2,typeof(a),typeof(a)==TYPE_FLOAT,typeof(typeof(a))]\n';
  for(const optimize of [true,false]){const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'number',numericType:'int'}}});for(const [x,v]of [[1,2.5],[0,0],[-1,-2.5],[2,5]]){const got=evaluate(program,{"'Policy'!E6":x});[v,3,true,2].forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));}assert.equal(program.outputNumericTypes['result[0]'],'float');}
  for(const optimize of [true,false])for(const name of ['lerpf','minf','maxf','roundf','signf','exp','log','tanh','pow']){const args=name==='lerpf'?'0,5,x':['pow','minf','maxf'].includes(name)?'x,2':'x',program=emitExcel(compileModel(`func run(x: int) -> Array:\n\treturn [typeof(${name}(${args})),typeof(typeof(${name}(${args})))]\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'number',numericType:'int'}}}),got=evaluate(program,{"'Policy'!E6":1});assert.equal(got.output('result[0]'),3,name);assert.equal(got.output('result[1]'),2,name);}
});
test('strict symbolic unary and mixed String arithmetic fail closed in both modes',()=>{
  for(const optimize of [true,false])for(const op of ['-','+']){const program=emitExcel(compileModel(`func run(x: Variant) -> Variant:\n\treturn ${op}x\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'number',numericType:'float'}}});
    for(const x of [true,'5',null])assert.equal(evaluate(program,{"'Policy'!E6":x}).output('result'),'#N/A',`unary ${op}, ${x}`);assert.equal(evaluate(program,{"'Policy'!E6":5}).output('result'),op==='-'?-5:5);
  }
  for(const optimize of [true,false])for(const expression of ['x + 1','1 + x','x - 1','x * 1'])assert.throws(()=>emitExcel(compileModel(`func run(x: String) -> Variant:\n\treturn ${expression}\n`,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'string'}}}),/non-numeric|String arithmetic/);
  for(const optimize of [true,false]){const program=emitExcel(compileModel('func run(x: String) -> String:\n\treturn x + "!"\n',{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'string'}}});assert.equal(evaluate(program,{"'Policy'!E6":'abc'}).output('result'),'abc!');assert.equal(evaluate(program,{"'Policy'!E6":true}).output('result'),'#N/A');}
});
test('deep duplicate recursively copies guarded container choices in both modes',()=>{
  const source='func run(x: bool,y: bool) -> Array:\n\tvar a := [1]\n\tvar b := [2]\n\tvar d := {"v": {"a": a if x else b} if y else {"a": b if x else a}}\n\tvar deep := d.duplicate(true)\n\ta[0] = 9\n\tb[0] = 8\n\tvar z := [3]\n\tvar shared := {"a":z,"b":z}.duplicate(true)\n\tshared.a[0] = 7\n\treturn [deep.v.a[0],shared.b[0],z[0]]\n';
  for(const optimize of [true,false]){const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'boolean'},y:{cell:"'Policy'!E7",type:'boolean'}}});for(const x of [true,false])for(const y of [true,false]){const got=evaluate(program,{"'Policy'!E6":x,"'Policy'!E7":y});[x===y?1:2,7,3].forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v,`deep ${x}/${y}, optimize=${optimize}`));}}
  const shallow=source.replace('var deep := d.duplicate(true)','var deep := d.duplicate(false)');for(const optimize of [true,false]){const program=emitExcel(compileModel(shallow,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'boolean'},y:{cell:"'Policy'!E7",type:'boolean'}}});for(const x of [true,false])for(const y of [true,false])assert.equal(evaluate(program,{"'Policy'!E6":x,"'Policy'!E7":y}).output('result[0]'),x===y?9:8);}
});
test('related intrinsic type/coercion and guarded deep-copy mutation have independent expectations',()=>{
  const tags='func run() -> Array:\n\treturn [typeof(float(1)),typeof(int(1.5)),typeof(str(1)),typeof(is_finite(1.0)),typeof(range(2)),TYPE_FLOAT/2,typeof(TYPE_FLOAT/2)]\n';
  const copy='func run(x: bool) -> Array:\n\tvar a := [1]\n\tvar b := [2]\n\tvar deep := {"direct":a,"selected":a if x else b}.duplicate(true)\n\tdeep.selected[0] = 7\n\treturn [deep.direct[0],a[0],b[0]]\n';
  const original='func run(x: bool) -> Array:\n\tvar a := [1]\n\tvar b := [2]\n\tvar d := {"a":a if x else b}\n\tvar deep := d.duplicate(true)\n\ta[0] = 9\n\tb[0] = 8\n\treturn deep.a\n';
  for(const optimize of [true,false]){
    const tagProgram=emitExcel(compileModel(tags,{entrypoints:['run']}),{entrypoint:'run',optimize});[3,2,4,1,28,1,2].forEach((v,i)=>assert.equal(evaluate(tagProgram).output(`result[${i}]`),v));
    for(const [source,expect]of [[copy,x=>[x?7:1,1,2]],[original,x=>[x?1:2]]]){const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'boolean'}}});for(const x of [true,false]){const got=evaluate(program,{"'Policy'!E6":x});expect(x).forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));}}
    for(const args of ['true,1,1','0,"5",1','0,5,false'])assert.throws(()=>emitExcel(compileModel(`func run() -> Variant:\n\treturn lerpf(${args})\n`,{entrypoints:['run']}),{entrypoint:'run',optimize}),/non-numeric math/);
  }
});
test('unproved numeric alternatives of nonnumeric schemas are not guessed by typeof',()=>{
  for(const optimize of [true,false])for(const type of ['boolean','string']){
    const arguments_={d:{v:{cell:"'Policy'!E6",type}}};
    const observed=compileModel('func run(d: Dictionary) -> Variant:\n\treturn typeof(d.v)\n',{entrypoints:['run']});
    assert.throws(()=>emitExcel(observed,{entrypoint:'run',optimize,arguments:arguments_}),/exact int\/float provenance/,'decline direct enum observation rather than guess float for an invalid numeric edit');
    const compared=compileModel('func run(d: Dictionary) -> Array:\n\treturn [typeof(d.v)==TYPE_BOOL,typeof(d.v)==TYPE_STRING,typeof(typeof(d.v))]\n',{entrypoints:['run']});
    const program=emitExcel(compared,{entrypoint:'run',optimize,arguments:arguments_});
    for(const [x,hand]of [[true,[true,false,2]],['s',[false,true,2]],[5,[false,false,2]],[null,[false,false,2]]]){const got=evaluate(program,{"'Policy'!E6":x});hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));}
    assert.equal(evaluate(program,{"'Policy'!E6":new CellError('#VALUE!')}).output('result[0]'),'#N/A','spreadsheet error is not a source String');
  }
});
test('symbolic negative writes normalize before bounds in both modes',()=>{
  const source='func run(i: int) -> Array:\n\tvar a := [1,2]\n\ta[i] = 8\n\treturn a\n';
  for(const optimize of [true,false]){const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{i:{cell:"'Policy'!E6",type:'number'}}});
    for(const [i,expected] of [[-1,[1,8]],[-2,[8,2]],[0,[8,2]],[1,[1,8]],[-3,['#N/A','#N/A']],[2,['#N/A','#N/A']]]){const got=evaluate(program,{"'Policy'!E6":i});expected.forEach((v,index)=>assert.equal(got.output(`result[${index}]`),v,`index ${i}, optimize=${optimize}`));}
  }
});
test('Variant/container numeric provenance has independent integer/float expectations in both modes',()=>{
  const source='func run() -> Array:\n\tvar a := [5,2]\n\tvar divided = a[0] / a[1]\n\ta[0] /= 2\n\tvar direct = 5\n\tvar floats := [5.0,2]\n\tvar d := {"v":5}\n\tvar copied := d.duplicate(true)\n\tcopied.merge({"f":5.0},true)\n\treturn [5/2,divided,a[0],direct/2,floats[0]/floats[1],copied.v/2,copied.f/2,[1,2,3,4,5].size()/2,typeof(a[0]) == TYPE_INT,typeof(floats[0]) == TYPE_FLOAT]\n';
  const hand=[2,2,2,2,2.5,2,2.5,2,true,true],ir=compileModel(source,{entrypoints:['run']});
  for(const optimize of [true,false]){const emitted=emitExcel(ir,{entrypoint:'run',optimize}),got=evaluate(emitted);hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));assert.equal(emitted.outputNumericTypes['result[0]'],'int');assert.equal(emitted.outputNumericTypes['result[4]'],'float');
    for(const body of ['return [true][0] + 1','var a := [true]\n\ta[0] /= 2\n\treturn a[0]'])assert.throws(()=>emitExcel(compileModel('func run() -> Variant:\n\t'+body+'\n',{entrypoints:['run']}),{entrypoint:'run',optimize}),/Boolean\/non-numeric/);
    const dynamic=compileModel('func run(x: Variant) -> Variant:\n\treturn x / 2\n',{entrypoints:['run']});
    assert.throws(()=>emitExcel(dynamic,{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'variant'}}}),/unproved Variant numeric division/);
    for(const [kind,expected] of [['int',2],['float',2.5]])assert.equal(evaluate(emitExcel(dynamic,{entrypoint:'run',optimize,arguments:{x:modelNumber(5,kind)}})).output('result'),expected);
    for(const [numericType,expected] of [['int',2],['float',2.5]]){const program=emitExcel(dynamic,{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'variant',numericType}}});assert.equal(evaluate(program,{"'Policy'!E6":5}).output('result'),expected);assert.equal(evaluate(program,{"'Policy'!E6":true}).output('result'),'#N/A');assert.equal(evaluate(program,{"'Policy'!E6":5.5}).output('result'),numericType==='int'?'#N/A':2.75);}
    const branch=compileModel('func run(x: float) -> Variant:\n\tvar a := [5]\n\tif x > 0:\n\t\ta[0] = 5.0\n\treturn a[0] / 2\n',{entrypoints:['run']});
    const program=emitExcel(branch,{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'number'}}});for(const [x,expected] of [[1,2.5],[-1,2]])assert.equal(evaluate(program,{"'Policy'!E6":x}).output('result'),expected);
  }
});
test('nested copy-on-write merges cannot claim objects borrowed from outer siblings',()=>{
  const source='func run(x: float,y: float) -> Array:\n\tvar a := [1.0,2.0]\n\tif x > 0:\n\t\tif y > 0:\n\t\t\tvar unused := 10.0\n\t\telse:\n\t\t\tvar unused := 20.0\n\t\ta.resize(1)\n\telse:\n\t\tvar copy := a.slice(1)\n\treturn a\n';
  const ir=compileModel(source,{entrypoints:['run']});for(const optimize of [true,false]){const program=emitExcel(ir,{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'number'},y:{cell:"'Policy'!E7",type:'number'}}});for(const x of [-1,1])for(const y of [-1,1]){const got=evaluate(program,{"'Policy'!E6":x,"'Policy'!E7":y});assert.equal(got.output('result[0]'),1);assert.equal(got.output('result[1]'),x>0?'#N/A':2);}}
  const mutation=source.replace('a.resize(1)','a[0] = 9.0');for(const optimize of [true,false]){const program=emitExcel(compileModel(mutation,{entrypoints:['run']}),{entrypoint:'run',optimize,arguments:{x:{cell:"'Policy'!E6",type:'number'},y:{cell:"'Policy'!E7",type:'number'}}});for(const x of [-1,1])for(const y of [-1,1]){const got=evaluate(program,{"'Policy'!E6":x,"'Policy'!E7":y});assert.equal(got.output('result[0]'),x>0?9:1);assert.equal(got.output('result[1]'),2);}}
});
test('lazy invalid branch and signed rounding formulas',()=>{
  const r=micro('func run(x: float) -> Array:\n\treturn [log(x) if x > 0 else 7.0, roundf(x), int(x)]\n',{x:{cell:"'Policy'!E6",type:'number'}},{"'Policy'!E6":-2.5});
  assert.equal(r.computed.output('result[0]'),7);assert.equal(r.computed.output('result[1]'),-3);assert.equal(r.computed.output('result[2]'),-2);
});
test('independent typed compound/assignment expectations in both paths',()=>{
  const source='func run(x: float, y: float) -> Array:\n\tvar a: int = x\n\ta /= y\n\tvar b: float = x\n\tb /= 2\n\tvar c: int = 7.9\n\tc += 0.9\n\tvar d := 5\n\td /= 2\n\treturn [a,b,c,d,5/2,5/2.0]\n';
  const ir=compileModel(source,{entrypoints:['run']}),program=emitExcel(ir,{entrypoint:'run',arguments:{x:{cell:"'Policy'!E6",type:'number'},y:{cell:"'Policy'!E7",type:'number'}}});
  for(const [x,y,expected] of [[5,2,2],[-5,2,-2],[5,-2,-2],[-5,-2,2]]){const got=evaluate(program,{"'Policy'!E6":x,"'Policy'!E7":y});const hand=[expected,x/2,7,2,2,2.5];hand.forEach((v,i)=>assert.equal(got.output(`result[${i}]`),v));assert.deepEqual(evaluateModel(ir,'run',[x,y]),hand);}
  const target=micro('func index(counter: Array) -> int:\n\tcounter[0] += 1\n\treturn 0\nfunc run() -> Array:\n\tvar counter := [0]\n\tvar a := [5.0]\n\ta[index(counter)] /= 2.0\n\treturn [a[0],counter[0]]\n',{});assert.equal(target.computed.output('result[0]'),2.5);assert.equal(target.computed.output('result[1]'),1);
});
test('formula rounding independently preserves large odd integers and signed near ties',()=>{
  const program=micro('func run(x: float) -> float:\n\treturn roundf(x)\n',{x:{cell:"'Policy'!E6",type:'number'}},{"'Policy'!E6":0}).program;
  for(const [x,expected] of [[2**52+1,2**52+1],[-(2**52+1),-(2**52+1)],[2**53-1,2**53-1],[.49999999999999994,0],[.5,1],[-.5,-1],[2.5,3],[-2.5,-3]])assert.equal(evaluate(program,{"'Policy'!E6":x}).output('result'),expected);
});
test('editable text equality is case-sensitive, Unicode-exact, type-safe; ordering rejects',()=>{
  const source='func run(x: Variant) -> Array:\n\treturn [x == "hold", x != "hold", x in ["hold","feedback"], x == "İ", x == 1]\n';
  const program=micro(source,{x:{cell:"'Policy'!E6",type:'variant'}},{"'Policy'!E6":''}).program;
  for(const [x,expected] of [['hold',[true,false,true,false,false]],['Hold',[false,true,false,false,false]],['Feedback',[false,true,false,false,false]],['İ',[false,true,false,true,false]],['i',[false,true,false,false,false]],[1,[false,true,false,false,true]],['1',[false,true,false,false,false]]])expected.forEach((v,i)=>assert.equal(evaluate(program,{"'Policy'!E6":x}).output(`result[${i}]`),v));
  assert.ok(Object.values(program.formulas).some(f=>f.includes('EXACT(')));
  assert.throws(()=>micro('func run(x: String) -> bool:\n\treturn x < "hold"\n',{x:{cell:"'Policy'!E6",type:'string'}}),/case-sensitive Unicode/);
});
test('unsafe lazy ranking and transitive mutation reject before any formulas',()=>{
  assert.throws(()=>micro('func run(x: float) -> int:\n\tvar a := [1]\n\twhile not a.is_empty():\n\t\tvar v := a.pop_back() if x > 0 else 0.0\n\treturn a.size()\n',{x:{cell:"'Policy'!E6",type:'number'}}),/decreasing/);
  const alias='func run() -> int:\n\tvar a := [1,2]\n\tvar b := a\n\twhile not a.is_empty() and not b.is_empty():\n\t\tvar x := a.pop_back()\n\treturn a.size()\n';
  assert.throws(()=>micro(alias,{}),/ranking arrays alias/);
});
test('exact guarded DAG reuse/liveness retain validation; sparse branch aliases stay independent',()=>{
  const source='func run(x: float) -> Array:\n\tvar unused := x * 99.0\n\tvar a := [1.0,2.0,3.0]\n\tvar alias := a\n\tvar checked := a[int(x)]\n\tif x > 0:\n\t\talias[0] = x * 2.0\n\t\ta[1] = x * 2.0\n\telse:\n\t\ta[2] = x * 3.0\n\treturn a\n';
  const ir=compileModel(source,{entrypoints:['run']}),bindings={entrypoint:'run',arguments:{x:{cell:"'Policy'!E6",type:'number'}}};
  const optimized=emitExcel(ir,bindings),unoptimized=emitExcel(ir,{...bindings,optimize:false});
  assert.ok(optimized.statistics.prunedHelpers>0);assert.ok(optimized.statistics.helperCells<unoptimized.statistics.helperCells);
  for(const x of [0,1,2,9])for(let i=0;i<3;i++){const expected=x===9?'#N/A':x>0?[x*2,x*2,3][i]:[1,2,x*3][i];assert.equal(evaluate(optimized,{"'Policy'!E6":x}).output(`result[${i}]`),expected);assert.equal(evaluate(unoptimized,{"'Policy'!E6":x}).output(`result[${i}]`),expected);}
  const typedDead=micro('func run(x: float) -> float:\n\tvar checked: int = x\n\treturn 1.0\n',{x:{cell:"'Policy'!E6",type:'number'}},{"'Policy'!E6":2**53});assert.equal(typedDead.computed.output('result'),'#N/A');
  const order=micro('func run(x: float) -> float:\n\treturn (10000000000000000.0 + x) - 10000000000000000.0\n',{x:{cell:"'Policy'!E6",type:'number'}},{"'Policy'!E6":1});assert.equal(order.computed.output('result'),0,'packing must preserve ordered rounding, not reassociate to x');assert.ok(order.program.statistics.packedSingleUseHelpers>0);assert.ok(order.program.sourceMap.some(x=>x.inlined||x.inlinedSources?.length));
  const dialect=evaluate({formulas:{"'Economy'!A1":'=TRUE'},outputs:{reference:"=MIN('Economy'!A1,2)",inline:'=MIN(TRUE,2)'}});assert.equal(dialect.output('reference'),2);assert.equal(dialect.output('inline'),1,'simulator must distinguish aggregation reference semantics');
});
test('context-specific array append-exclusion bounds are structural, including copies and independent events',()=>{
  const source='func run(x: float) -> int:\n\tvar a := []\n\tvar b := []\n\tfor i in range(4):\n\t\tif x > i:\n\t\t\ta.append(1)\n\t\telse:\n\t\t\tb.append(2)\n\twhile not a.is_empty() and not b.is_empty():\n\t\tvar aa := a.pop_back()\n\t\tvar bb := b.pop_back()\n\treturn a.size() + b.size()\n';
  const ir=compileModel(source,{entrypoints:['run']}),program=emitExcel(ir,{entrypoint:'run',arguments:{x:{cell:"'Policy'!E6",type:'number'}}});
  assert.ok(program.coverage.loopProofs.some(p=>p.sizeProof?.bound===4&&p.sizeProof?.capacity===8));
  for(const [x,left] of [[-1,4],[.5,2],[1.5,0],[2.5,2],[9,4]])assert.equal(evaluate(program,{"'Policy'!E6":x}).output('result'),left);
  const copy=micro('func run() -> int:\n\tvar original := [1,2,3]\n\tvar a := original.duplicate()\n\twhile not a.is_empty():\n\t\tvar v := a.pop_back()\n\treturn a.size()\n',{});assert.equal(copy.computed.output('result'),0);
  const independent=micro('func run() -> int:\n\tvar a := []\n\tvar b := []\n\tfor i in range(4):\n\t\ta.append(1)\n\t\tb.append(2)\n\twhile not a.is_empty() and not b.is_empty():\n\t\tvar aa := a.pop_back()\n\t\tvar bb := b.pop_back()\n\treturn a.size() + b.size()\n',{});assert.equal(independent.computed.output('result'),0);assert.ok(independent.program.coverage.loopProofs.some(p=>p.sizeProof?.bound===8));
});
test('aliasing, branch mutations, bounded iteration and merge precedence',()=>{
  const r=micro('func run(x: float) -> Dictionary:\n\tvar a := [1.0, 2.0]\n\tvar b := a\n\tif x > 0:\n\t\tb[0] += x\n\tfor i in range(2):\n\t\ta[i] *= 2.0\n\tvar d := {"a": a, "z": true}\n\td.merge({"z": false}, false)\n\treturn d\n',{x:{cell:"'Policy'!E6",type:'number'}},{"'Policy'!E6":3});
  assert.equal(r.computed.output('a[0]'),8);assert.equal(r.computed.output('a[1]'),4);assert.equal(r.computed.output('z'),true);
});
test('integer division, deep/shallow copies, early-return aliases and overwrite flags',()=>{
  const source='func resize_if(a: Array, x: float) -> Array:\n\tif x < 0:\n\t\treturn a\n\ta.resize(1)\n\treturn a\nfunc run(x: float) -> Dictionary:\n\tvar a := [3.0, 4.0]\n\tvar b := {"a": a}\n\tvar shallow := b.duplicate()\n\tvar deep := b.duplicate(true)\n\ta[0] += 1.0\n\tvar r := resize_if(a, x)\n\tvar d := {"z": 1.0}\n\td.merge({"z": 2.0}, x > 0)\n\tvar integer := -5\n\treturn {"r":r,"shallow":shallow,"deep":deep,"d":d,"integer":integer / 2}\n';
  for(const x of [-1,1]){const r=micro(source,{x:{cell:"'Policy'!E6",type:'number'}},{"'Policy'!E6":x});assert.equal(r.computed.output('r[0]'),4);assert.equal(r.computed.output('shallow.a[0]'),4);assert.equal(r.computed.output('deep.a[0]'),3);assert.equal(r.computed.output('d.z'),x>0?2:1);assert.equal(r.computed.output('integer'),-2);if(x<0)assert.equal(r.computed.output('r[1]'),4);else assert.equal(r.computed.output('r[1]'),'#N/A');}
});
test('optional dictionary presence and Boolean/numeric Variant checks',()=>{
  const source='func run(d: Dictionary) -> Dictionary:\n\treturn {"value":d.get("x", 9.0), "present":d.has("x"), "type":typeof(d.get("x"))}\n';
  const program=emitExcel(compileModel(source,{entrypoints:['run']}),{entrypoint:'run',arguments:{d:{x:{$optional:true,present:{cell:"'Policy'!E12",type:'boolean'},value:{cell:"'Policy'!E6",type:'variant',numericType:'float'}}}}});
  for(const [present,value,expectedType] of [[false,3,0],[true,3,3],[true,true,1],[true,'hello',4]]){const got=evaluate(program,{"'Policy'!E12":present,"'Policy'!E6":value});assert.equal(got.output('value'),present?value:9);assert.equal(got.output('present'),present);assert.equal(got.output('type'),expectedType);}
  const equal=micro('func run(x: Variant) -> Array:\n\treturn [x == 1, x == true]\n',{x:{cell:"'Policy'!E6",type:'variant'}},{"'Policy'!E6":true});assert.equal(equal.computed.output('result[0]'),false);assert.equal(equal.computed.output('result[1]'),true);
});
test('unknown output and dynamic range reject without partial programs',()=>{
  assert.throws(()=>emitExcel(compileModel(text('x'),{entrypoints:['run']}),{...bindings,outputs:{typo:"'Economy'!E20"}}),/unknown output/);
  assert.throws(()=>compileModel('func run(x: int) -> float:\n\tvar total := 0.0\n\tfor i in range(x):\n\t\ttotal += i\n\treturn total\n',{entrypoints:['run']}),/range loop bound/);
  for(const cell of ["'[external.xlsx]Sheet'!A1","'Policy'!XFE1","'Policy'!A1048577"]){assert.throws(()=>emitExcel(compileModel(text('x'),{entrypoints:['run']}),{...bindings,arguments:{x:{cell,type:'number'}}}),/local A1/);}
  assert.throws(()=>emitExcel(compileModel(text('x * 2'),{entrypoints:['run']}),{...bindings,helperSheet:'Policy',helperColumn:'A',helperStartRow:1}),/collision/);
  assert.throws(()=>emitExcel(compileModel(text('x'),{entrypoints:['run']}),{...bindings,outputs:{result:"'Policy'!A1"}}),/collision/);
  const changed=compileModel(text('x'),{entrypoints:['run']});changed.functions.run.body=[];assert.throws(()=>emitExcel(changed,bindings),/fingerprint/);
  const dynamic=compileModel('func run(x: String) -> Dictionary:\n\tvar d := {}\n\td[x] = 1.0\n\treturn d\n',{entrypoints:['run']});assert.throws(()=>emitExcel(dynamic,{entrypoint:'run',arguments:{x:{cell:"'Policy'!E6",type:'string'}}}),/output key/);
});
test('mutating an iteration domain fails rather than truncating a loop',()=>{
  const ir=compileModel('func run() -> Array:\n\tvar a := [1.0]\n\tfor x in a:\n\t\ta.append(x)\n\treturn a\n',{entrypoints:['run']});assert.throws(()=>emitExcel(ir,{entrypoint:'run'}),/iteration proof/);
  const ir2=compileModel('func run(x: String) -> bool:\n\treturn x.is_valid_float()\n',{entrypoints:['run']});assert.throws(()=>emitExcel(ir2,{entrypoint:'run',arguments:{x:{cell:"'Policy'!E6",type:'string'}}}),/literal source string/);
});
const source=fs.readFileSync(new URL('../../game/model/economy.gd',import.meta.url),'utf8');
const ir=compileModel(source);
// These resident source/reference JSON numbers have an explicit floating input
// contract; this is not integer-looking inference. Source literals retain tags.
const canonical=(name,args,options={})=>evaluateModel(ir,name,args,{numericInputs:'float',...options});
test('a real canonical equation edit propagates without a backend edit',()=>{
  const changed=source.replace('scale * tanh(rate / scale)','0.5 * scale * tanh(rate / scale)');assert.notEqual(changed,source);
  const edited=compileModel(changed),arguments_={rate:{cell:"'Policy'!E6",type:'number'},scale:1.0};
  const original=emitExcel(ir,{entrypoint:'_effective_rate',arguments:arguments_,outputs:{result:"'Economy'!E20"}}),candidate=emitExcel(edited,{entrypoint:'_effective_rate',arguments:arguments_,outputs:{result:"'Economy'!E20"}});
  assert.notDeepEqual(original.formulas,candidate.formulas);assert.notEqual(original.provenance.canonicalSourceSha256,candidate.provenance.canonicalSourceSha256);
  const actual=evaluate(candidate,{"'Policy'!E6":-1}).output('result');assert.equal(actual,evaluateModel(edited,'_effective_rate',[-1,1]));assert.notEqual(actual,evaluate(original,{"'Policy'!E6":-1}).output('result'));
});
const read=name=>JSON.parse(fs.readFileSync(new URL('../../game/model/'+name,import.meta.url)));
const parameters=Object.fromEntries(read('parameters.json').map(({key,value})=>[key,value]));
const portfolio=read('portfolio_reference.json');
const initial=canonical('initial_state',[parameters,{}],{inputs:{portfolio}});
const taggedInitial=canonical('initial_state',[parameters,{}],{inputs:{portfolio},preserveNumericTypes:true});
assert.equal(initial.ok,true);
assert.equal(numericKind(taggedInitial.state.quarter_index),'int','source literal quarter zero is an integer, not inferred from its value');
const initialBytes=JSON.stringify(initial.state);
const cells={};let inputIndex=0;
const bind=(value,template)=>{
  if(isModelNumber(value))return bind(value.value,value);
  if(Array.isArray(value))return value.map((v,i)=>bind(v,template?.[i]));
  if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,bind(v,template?.[k])]));
  if(typeof value==='number'||typeof value==='boolean'){const cell="'Assumptions'!A"+(++inputIndex);cells[cell]=value;return {cell,type:typeof value,...(typeof value==='number'?{numericType:isModelNumber(template)?numericKind(template):'float'}:{})};}
  return value;
};
const compareOutputs=(program,got,expected,prefix)=>{let fields=0;
  function compare(value,path){if(Array.isArray(value))return value.forEach((v,i)=>compare(v,`${path}[${i}]`));if(value&&typeof value==='object')return Object.entries(value).forEach(([k,v])=>compare(v,path?path+'.'+k:k));fields++;const actual=got.output(path||'result');if(typeof value==='number')assert.ok(typeof actual==='number'&&Math.abs(actual-value)<1e-7,`${path}: ${actual} vs ${value}`);else assert.equal(actual,value,path);}
  compare(expected,prefix);return fields;
};
test('canonical initialization emits and matches all pure IR state outputs',()=>{
  const program=emitExcel(ir,{entrypoint:'initial_state',arguments:{params:bind(parameters),override:{}},inputs:{portfolio:bind(portfolio)}});
  recordCoverage(program);
  const got=evaluate(program,cells);let fields=0;
  function compare(value,path){if(Array.isArray(value))return value.forEach((v,i)=>compare(v,`${path}[${i}]`));if(value&&typeof value==='object')return Object.entries(value).forEach(([k,v])=>compare(v,path+'.'+k));fields++;const actual=got.output(path);if(typeof value==='number')assert.ok(typeof actual==='number'&&Math.abs(actual-value)<1e-7,`${path}: ${actual} vs ${value}`);else assert.equal(actual,value,path);}
  compare(initial.state,'state');assert.equal(fields,373);assert.ok(program.coverage.functions.includes('_validate_state'));
  assert.deepEqual([...got.cache].filter(([,v])=>v instanceof CellError).map(([cell])=>({cell,formula:program.formulas[cell],source:program.sourceMap.find(x=>x.cell===cell)?.source})),[],'valid initialization has no erroneous helper cells');
  console.log(JSON.stringify({canonicalInitialCells:program.statistics.helperCells,fields,emissionMilliseconds:program.statistics.elapsedMilliseconds,statistics:program.statistics}));
});
test('one initialization program handles every shipped optional override schema',()=>{
  const override=Object.fromEntries(modelConstants(ir).INITIAL_OVERRIDE_KEYS.map(key=>[key,{$optional:true,present:bind(false),value:bind(0)}]));
  const program=emitExcel(ir,{entrypoint:'initial_state',arguments:{params:bind(parameters),override},inputs:{portfolio:bind(portfolio)}});
  for(const scenario of read('scenarios.json')){
    const local={...cells};for(const [key,entry] of Object.entries(override)){local[entry.present.cell]=Object.hasOwn(scenario.initial,key);local[entry.value.cell]=scenario.initial[key]??0;}
    const expected=canonical('initial_state',[parameters,scenario.initial],{inputs:{portfolio}}),actual=evaluate(program,local);assert.equal(expected.ok,true);compareOutputs(program,actual,expected,'');assert.equal([...actual.cache.values()].filter(x=>x instanceof CellError).length,0,scenario.id+' initializer helper errors');
  }
});
test('canonical step, financial helpers and full state/trace match pure IR',()=>{
  const policy={...canonical('benchmark_policy',[initial.state,parameters]),reinvest_principal:true,maintain_ample_reserves:true,sterilize_purchases:false};
  const shocks=Object.fromEntries(Object.keys(modelConstants(ir).SHOCK_LIMITS).map(key=>[key,key==='potential_growth_pct'?2:key==='rrp_uptake_fraction'?1:0]));
  const expected=canonical('step',[initial.state,policy,shocks,parameters]);assert.equal(expected.ok,true);
  const args={state:bind(initial.state,taggedInitial.state),policy:bind(policy),shocks:bind(shocks),params:bind(parameters)};
  const program=emitExcel(ir,{entrypoint:'step',arguments:args});
  recordCoverage(program);
  const got=evaluate(program,cells);
  if(got.output('ok')!==true)console.log('STEP FAILURE',got.output('ok'),got.output('error'),program.diagnostics.filter(d=>d.kind==='return-arm'&&['step','_balance_sheet_step','_validate_state','_principal_net'].includes(d.function)&&(d.condition==='TRUE'||got.cache.get(d.condition)===true)).slice(-12));
  if(got.output('ok')!==true)console.log('LIVE UNAVAILABLE',program.diagnostics.filter(d=>d.kind==='unavailable-guard'&&(d.condition==='TRUE'||got.cache.get(d.condition)===true)).slice(0,12),'HELPER ERRORS',[...got.cache].filter(([,v])=>v instanceof CellError).slice(0,5).map(([cell])=>({cell,formula:program.formulas[cell],source:program.sourceMap.find(x=>x.cell===cell)})));
  const fields=compareOutputs(program,got,expected,'');assert.equal(fields,1+373+Object.keys(expected.trace).length);assert.ok(program.coverage.functions.includes('_principal_net'));
  const errors=[...got.cache].filter(([,v])=>v instanceof CellError);assert.equal(errors.length,0,'valid transition has no erroneous helper cells: '+JSON.stringify(errors.slice(0,8).map(([cell])=>({cell,formula:program.formulas[cell],source:program.sourceMap.find(x=>x.cell===cell)?.source}))));
  console.log(JSON.stringify({canonicalStepCells:program.statistics.helperCells,fields,emissionMilliseconds:program.statistics.elapsedMilliseconds,statistics:program.statistics}));
  if(process.env.FED_MODEL_METRICS){const counts={};for(const item of program.sourceMap){const line=item.source?.line??0;counts[line]=(counts[line]??0)+1;}console.log(JSON.stringify({transitionTopSourceLines:Object.entries(counts).sort((a,b)=>b[1]-a[1]).slice(0,12)}));}
  for(let bits=0;bits<8;bits++){
    const local={...cells},decision={...policy,asset_flow_request_pct_initial_gdp:2,liquidity_request_pct_initial_gdp:1};
    for(const [i,key] of ['reinvest_principal','maintain_ample_reserves','sterilize_purchases'].entries())decision[key]=Boolean(bits&(1<<i));
    for(const [key,value] of Object.entries(decision))local[args.policy[key].cell]=value;
    const expectation=canonical('step',[initial.state,decision,shocks,parameters]);const actual=evaluate(program,local);compareOutputs(program,actual,expectation,'');
    assert.equal([...actual.cache.values()].filter(x=>x instanceof CellError).length,0,'valid switches must not produce inactive helper errors');
  }
  for(const [key,value] of [['policy_rate_request_pct',true],['reinvest_principal',0],['guidance_rate_pct',3.501],['liquidity_request_pct_initial_gdp',-1]]){
    const local={...cells,[args.policy[key].cell]:value},actual=evaluate(program,local),expected=canonical('step',[initial.state,{...policy,[key]:value},shocks,parameters]);assert.equal(actual.output('ok'),false,`invalid ${key} must not succeed`);assert.equal(actual.output('error'),expected.error);assert.equal(actual.output('state.actual_output_index'),'#N/A');
  }
  for(const [field,index,value] of [['treasury_cohorts_pct_initial_gdp',0,-1],['sterilized_treasury_cohorts_pct_initial_gdp',1,1e5],['reserves_pct_initial_gdp',null,'wrong'],['guidance_active',null,1]]){
    const state=structuredClone(initial.state),local={...cells};if(index===null){state[field]=value;local[args.state[field].cell]=value;}else{state[field][index]=value;local[args.state[field][index].cell]=value;}
    const expected=canonical('step',[state,policy,shocks,parameters]),actual=evaluate(program,local);assert.equal(expected.ok,false);assert.equal(actual.output('ok'),false);assert.equal(actual.output('error'),expected.error);assert.equal(actual.output('state.actual_output_index'),'#N/A');
  }
  for(const maturity of [1,23.6,120]){
    const local={...cells,[args.params.treasury_reinvestment_maturity_quarters.cell]:maturity},decision={...policy,asset_flow_request_pct_initial_gdp:2,sterilize_purchases:true};
    local[args.policy.asset_flow_request_pct_initial_gdp.cell]=2;local[args.policy.sterilize_purchases.cell]=true;
    const expected=canonical('step',[initial.state,decision,shocks,{...parameters,treasury_reinvestment_maturity_quarters:maturity}]),actual=evaluate(program,local);compareOutputs(program,actual,expected,'');assert.equal([...actual.cache.values()].filter(x=>x instanceof CellError).length,0);
  }
});
test('source principal cancellation algorithm, not a backend financial template',()=>{
  const cases=[[8,4,-5,-7],[1e308,1e308,-1e308,-1e308],[0,0],[-2,3,-1],[7,-2,-3],[1,1,-1,-1,1e-12]];
  const sourceIR=compileModel(source,{entrypoints:['_principal_net']});
  const handExpected=[0,0,0,0,2,1e-12];
  for(const [i,legs] of cases.entries()){const program=emitExcel(sourceIR,{entrypoint:'_principal_net',arguments:{legs:bind(legs)}});const calculation=evaluate(program,cells),got=calculation.output('result');const expected=evaluateModel(sourceIR,'_principal_net',[legs]);assert.ok(typeof got==='number'&&Math.abs(got-expected)<1e-12,`${JSON.stringify(legs)}: ${got} vs ${expected}`);assert.ok(Math.abs(got-handExpected[i])<1e-15,'independent cancellation expectation');assert.equal([...calculation.cache.values()].filter(x=>x instanceof CellError).length,0);}
});
test('all canonical benchmark branches emit source-derived policies',()=>{
  for(const kind of ['hold','feedback','neutral']){
    const program=emitExcel(ir,{entrypoint:'benchmark_policy',arguments:{state:bind(initial.state),params:bind(parameters),kind}});
    recordCoverage(program);
    compareOutputs(program,evaluate(program,cells),canonical('benchmark_policy',[initial.state,parameters,kind]),'');
  }
});
test('canonical editable benchmark names reject case variants; large grid quotes stay valid',()=>{
  const program=emitExcel(ir,{entrypoint:'benchmark_policy',arguments:{state:bind(initial.state),params:bind(parameters),kind:{cell:"'Policy'!E6",type:'string'}}});
  for(const kind of ['Hold','Feedback','HOLD','feedback ','İ']){
    const got=evaluate(program,{...cells,"'Policy'!E6":kind});assert.equal(got.output('ok'),false);assert.equal(got.output('error'),'unknown benchmark policy: '+kind);assert.equal(got.output('policy_rate_request_pct'),'#N/A');
  }
  for(const kind of ['hold','feedback','neutral'])compareOutputs(program,evaluate(program,{...cells,"'Policy'!E6":kind}),canonical('benchmark_policy',[initial.state,parameters,kind]),'');
  assert.deepEqual(program.requirements.unqualifiedNewPrimitives,['EXACT']);
  const grid=emitExcel(ir,{entrypoint:'_rate_on_grid',arguments:{rate:{cell:"'Policy'!E6",type:'number'},increment:.25}});
  for(const units of [2**52+1,-(2**52+1),1,-1,0]){assert.equal(evaluate(grid,{"'Policy'!E6":units/4}).output('result'),true);assert.equal(canonical('_rate_on_grid',[units/4,.25]),true);}
  assert.equal(evaluate(grid,{"'Policy'!E6":.3}).output('result'),false);
});
test('entire compiled canonical function graph has emitted coverage',()=>{
  assert.deepEqual(ir.coverage.functions.filter(name=>!emittedFunctions.has(name)),[]);
  const backend=fs.readFileSync(new URL('../spreadsheet/model-excel.mjs',import.meta.url),'utf8');
  for(const name of ['_principal_net','_balance_sheet_step','_portfolio_premium','inflation_target_pct','funding_need_pct_initial_gdp'])assert.equal(backend.includes(name),false,'backend must not key economic templates to '+name);
});
if(process.env.FED_MODEL_REFERENCE_DIR){
  test('resident hash-bound native exports independently check the generic IR and formulas',()=>{
    const directory=process.env.FED_MODEL_REFERENCE_DIR,provenance=JSON.parse(fs.readFileSync(path.join(directory,'../evidence/build-provenance.json')));
    const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
    for(const name of ['economy.gd','parameters.json','scenarios.json','exogenous_shocks.json','portfolio_reference.json'])assert.equal(sha(fs.readFileSync(new URL('../../game/model/'+name,import.meta.url))),provenance.model_sha256[name],`retained source binding ${name}`);
    for(const name of ['base','supply_shock','unanchored_inflation']){
      const bytes=fs.readFileSync(path.join(directory,name+'.json'));assert.equal(sha(bytes),provenance.references_sha256[name+'.json']);const fixture=JSON.parse(bytes),row=fixture.quarters[0];
      const expected={ok:true,state:row.state,trace:row.trace};const interpreted=canonical('step',[fixture.initial_state,row.policy,row.shock,parameters]);assert.equal(interpreted.ok,true);
      const program=emitExcel(ir,{entrypoint:'step',arguments:{state:bind(fixture.initial_state,taggedInitial.state),policy:bind(row.policy),shocks:bind(row.shock),params:bind(parameters)}});
      compareOutputs(program,evaluate(program,cells),expected,'');
      const compareRecord=(actual,expected,label)=>{
        if(Array.isArray(expected)){assert.equal(actual.length,expected.length,label);expected.forEach((v,i)=>compareRecord(actual[i],v,`${label}[${i}]`));}
        else if(expected&&typeof expected==='object'){assert.deepEqual(Object.keys(actual).sort(),Object.keys(expected).sort(),label);for(const [key,value] of Object.entries(expected))compareRecord(actual[key],value,label+'.'+key);}
        else if(typeof expected==='number')assert.ok(typeof actual==='number'&&Math.abs(actual-expected)<1e-7,`${label}: ${actual} vs ${expected}`);
        else assert.equal(actual,expected,label);
      };compareRecord(interpreted,expected,name);compareRecord(canonical('initial_state',[parameters,fixture.scenario.initial],{inputs:{portfolio}}),{ok:true,state:fixture.initial_state},name+' native initializer');
    }
    const bytes=fs.readFileSync(path.join(directory,'balance-boundaries.json'));assert.equal(sha(bytes),provenance.references_sha256['balance-boundaries.json']);const boundaries=JSON.parse(bytes);
    for(const name of ['uncapped_loan_refinancing','tagged_reinvestment_26','joint_aggregate_scarcity']){
      const fixture=boundaries.find(x=>x.name===name);assert.ok(fixture,`retained boundary ${name}`);const q=fixture.shocks.length-1,params={...parameters,...fixture.parameter_overrides},expected={ok:true,state:fixture.states[q+1],trace:fixture.traces[q]};
      const program=emitExcel(ir,{entrypoint:'step',arguments:{state:bind(fixture.states[q],taggedInitial.state),policy:bind(fixture.policies[q]),shocks:bind(fixture.shocks[q]),params:bind(params)}});
      const actual=evaluate(program,cells);compareOutputs(program,actual,expected,'');assert.equal([...actual.cache.values()].filter(x=>x instanceof CellError).length,0,`retained ${name} helper errors`);
    }
    console.log('PASS: six known development snapshots (three cold-first, three financial-boundary); retained data only, no fresh Godot or spreadsheet engine');
  });
}else console.log('NOT RUN: resident native-export comparison (set FED_MODEL_REFERENCE_DIR; no retrieval)');
assert.equal(JSON.stringify(initial.state),initialBytes,'pure probes preserve their shared predecessor state');
console.log(`PASS: ${checks} emitter tests; formula simulation only, native NOT RUN`);
console.log(JSON.stringify({rssBytesAtEnd:process.memoryUsage().rss,heapUsedBytesAtEnd:process.memoryUsage().heapUsed,peakRssBytes:process.resourceUsage().maxRSS*1024,compiledFunctions:ir.coverage.functions.length,emittedCanonicalFunctions:ir.coverage.functions.filter(name=>emittedFunctions.has(name)).length}));
