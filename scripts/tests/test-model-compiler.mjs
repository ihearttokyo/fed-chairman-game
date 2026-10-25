import assert from 'node:assert/strict';
import fs from 'node:fs';
import { compileModel, evaluateModel, roundAway, modelNumber } from '../spreadsheet/model-compiler.mjs';

let checks = 0;
const test = (name, run) => { if(process.env.FED_MODEL_TEST_FILTER&&!name.includes(process.env.FED_MODEL_TEST_FILTER))return;run(); checks++; console.log(`PASS ${name}`); };
const unit = body => `extends RefCounted\nfunc run(x: float) -> Variant:\n${body}\n`;
const compile = text => compileModel(text, { entrypoints: ['run'] });
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
