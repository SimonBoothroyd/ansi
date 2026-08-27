(function dartProgram(){function copyProperties(a,b){var s=Object.keys(a)
for(var r=0;r<s.length;r++){var q=s[r]
b[q]=a[q]}}function mixinPropertiesHard(a,b){var s=Object.keys(a)
for(var r=0;r<s.length;r++){var q=s[r]
if(!b.hasOwnProperty(q)){b[q]=a[q]}}}function mixinPropertiesEasy(a,b){Object.assign(b,a)}var z=function(){var s=function(){}
s.prototype={p:{}}
var r=new s()
if(!(Object.getPrototypeOf(r)&&Object.getPrototypeOf(r).p===s.prototype.p))return false
try{if(typeof navigator!="undefined"&&typeof navigator.userAgent=="string"&&navigator.userAgent.indexOf("Chrome/")>=0)return true
if(typeof version=="function"&&version.length==0){var q=version()
if(/^\d+\.\d+\.\d+\.\d+$/.test(q))return true}}catch(p){}return false}()
function inherit(a,b){a.prototype.constructor=a
a.prototype["$i"+a.name]=a
if(b!=null){if(z){Object.setPrototypeOf(a.prototype,b.prototype)
return}var s=Object.create(b.prototype)
copyProperties(a.prototype,s)
a.prototype=s}}function inheritMany(a,b){for(var s=0;s<b.length;s++){inherit(b[s],a)}}function mixinEasy(a,b){mixinPropertiesEasy(b.prototype,a.prototype)
a.prototype.constructor=a}function mixinHard(a,b){mixinPropertiesHard(b.prototype,a.prototype)
a.prototype.constructor=a}function lazy(a,b,c,d){var s=a
a[b]=s
a[c]=function(){if(a[b]===s){a[b]=d()}a[c]=function(){return this[b]}
return a[b]}}function lazyFinal(a,b,c,d){var s=a
a[b]=s
a[c]=function(){if(a[b]===s){var r=d()
if(a[b]!==s){A.vY(b)}a[b]=r}var q=a[b]
a[c]=function(){return q}
return q}}function makeConstList(a,b){if(b!=null)A.n(a,b)
a.$flags=7
return a}function convertToFastObject(a){function t(){}t.prototype=a
new t()
return a}function convertAllToFastObject(a){for(var s=0;s<a.length;++s){convertToFastObject(a[s])}}var y=0
function instanceTearOffGetter(a,b){var s=null
return a?function(c){if(s===null)s=A.nK(b)
return new s(c,this)}:function(){if(s===null)s=A.nK(b)
return new s(this,null)}}function staticTearOffGetter(a){var s=null
return function(){if(s===null)s=A.nK(a).prototype
return s}}var x=0
function tearOffParameters(a,b,c,d,e,f,g,h,i,j){if(typeof h=="number"){h+=x}return{co:a,iS:b,iI:c,rC:d,dV:e,cs:f,fs:g,fT:h,aI:i||0,nDA:j}}function installStaticTearOff(a,b,c,d,e,f,g,h){var s=tearOffParameters(a,true,false,c,d,e,f,g,h,false)
var r=staticTearOffGetter(s)
a[b]=r}function installInstanceTearOff(a,b,c,d,e,f,g,h,i,j){c=!!c
var s=tearOffParameters(a,false,c,d,e,f,g,h,i,!!j)
var r=instanceTearOffGetter(c,s)
a[b]=r}function setOrUpdateInterceptorsByTag(a){var s=v.interceptorsByTag
if(!s){v.interceptorsByTag=a
return}copyProperties(a,s)}function setOrUpdateLeafTags(a){var s=v.leafTags
if(!s){v.leafTags=a
return}copyProperties(a,s)}function updateTypes(a){var s=v.types
var r=s.length
s.push.apply(s,a)
return r}function updateHolder(a,b){copyProperties(b,a)
return a}var hunkHelpers=function(){var s=function(a,b,c,d,e){return function(f,g,h,i){return installInstanceTearOff(f,g,a,b,c,d,[h],i,e,false)}},r=function(a,b,c,d){return function(e,f,g,h){return installStaticTearOff(e,f,a,b,c,[g],h,d)}}
return{inherit:inherit,inheritMany:inheritMany,mixin:mixinEasy,mixinHard:mixinHard,installStaticTearOff:installStaticTearOff,installInstanceTearOff:installInstanceTearOff,_instance_0u:s(0,0,null,["$0"],0),_instance_1u:s(0,1,null,["$1"],0),_instance_2u:s(0,2,null,["$2"],0),_instance_0i:s(1,0,null,["$0"],0),_instance_1i:s(1,1,null,["$1"],0),_instance_2i:s(1,2,null,["$2"],0),_static_0:r(0,null,["$0"],0),_static_1:r(1,null,["$1"],0),_static_2:r(2,null,["$2"],0),makeConstList:makeConstList,lazy:lazy,lazyFinal:lazyFinal,updateHolder:updateHolder,convertToFastObject:convertToFastObject,updateTypes:updateTypes,setOrUpdateInterceptorsByTag:setOrUpdateInterceptorsByTag,setOrUpdateLeafTags:setOrUpdateLeafTags}}()
function initializeDeferredHunk(a){x=v.types.length
a(hunkHelpers,v,w,$)}var J={
nR(a,b,c,d){return{i:a,p:b,e:c,x:d}},
mz(a){var s,r,q,p,o,n=a[v.dispatchPropertyName]
if(n==null)if($.nP==null){A.vl()
n=a[v.dispatchPropertyName]}if(n!=null){s=n.p
if(!1===s)return n.i
if(!0===s)return a
r=Object.getPrototypeOf(a)
if(s===r)return n.i
if(n.e===r)throw A.a(A.nl("Return interceptor for "+A.y(s(a,n))))}q=a.constructor
if(q==null)p=null
else{o=$.lO
if(o==null)o=$.lO=v.getIsolateTag("_$dart_js")
p=q[o]}if(p!=null)return p
p=A.vq(a)
if(p!=null)return p
if(typeof a=="function")return B.b0
s=Object.getPrototypeOf(a)
if(s==null)return B.ab
if(s===Object.prototype)return B.ab
if(typeof q=="function"){o=$.lO
if(o==null)o=$.lO=v.getIsolateTag("_$dart_js")
Object.defineProperty(q,o,{value:B.E,enumerable:false,writable:true,configurable:true})
return B.E}return B.E},
oq(a,b){if(a<0||a>4294967295)throw A.a(A.S(a,0,4294967295,"length",null))
return J.rA(new Array(a),b)},
rz(a,b){if(a<0)throw A.a(A.M("Length must be a non-negative integer: "+a,null))
return A.n(new Array(a),b.h("t<0>"))},
op(a,b){if(a<0)throw A.a(A.M("Length must be a non-negative integer: "+a,null))
return A.n(new Array(a),b.h("t<0>"))},
rA(a,b){var s=A.n(a,b.h("t<0>"))
s.$flags=1
return s},
rB(a,b){return J.qT(a,b)},
cB(a){if(typeof a=="number"){if(Math.floor(a)==a)return J.dK.prototype
return J.fp.prototype}if(typeof a=="string")return J.bu.prototype
if(a==null)return J.dL.prototype
if(typeof a=="boolean")return J.fo.prototype
if(Array.isArray(a))return J.t.prototype
if(typeof a!="object"){if(typeof a=="function")return J.ax.prototype
if(typeof a=="symbol")return J.cL.prototype
if(typeof a=="bigint")return J.ai.prototype
return a}if(a instanceof A.l)return a
return J.mz(a)},
au(a){if(typeof a=="string")return J.bu.prototype
if(a==null)return a
if(Array.isArray(a))return J.t.prototype
if(typeof a!="object"){if(typeof a=="function")return J.ax.prototype
if(typeof a=="symbol")return J.cL.prototype
if(typeof a=="bigint")return J.ai.prototype
return a}if(a instanceof A.l)return a
return J.mz(a)},
bj(a){if(a==null)return a
if(Array.isArray(a))return J.t.prototype
if(typeof a!="object"){if(typeof a=="function")return J.ax.prototype
if(typeof a=="symbol")return J.cL.prototype
if(typeof a=="bigint")return J.ai.prototype
return a}if(a instanceof A.l)return a
return J.mz(a)},
vg(a){if(typeof a=="number")return J.cK.prototype
if(typeof a=="string")return J.bu.prototype
if(a==null)return a
if(!(a instanceof A.l))return J.ce.prototype
return a},
nM(a){if(typeof a=="string")return J.bu.prototype
if(a==null)return a
if(!(a instanceof A.l))return J.ce.prototype
return a},
nN(a){if(a==null)return a
if(typeof a!="object"){if(typeof a=="function")return J.ax.prototype
if(typeof a=="symbol")return J.cL.prototype
if(typeof a=="bigint")return J.ai.prototype
return a}if(a instanceof A.l)return a
return J.mz(a)},
a_(a,b){if(a==null)return b==null
if(typeof a!="object")return b!=null&&a===b
return J.cB(a).a3(a,b)},
qP(a,b){if(typeof b==="number")if(Array.isArray(a)||typeof a=="string"||A.q9(a,a[v.dispatchPropertyName]))if(b>>>0===b&&b<a.length)return a[b]
return J.au(a).j(a,b)},
nZ(a,b,c){if(typeof b==="number")if((Array.isArray(a)||A.q9(a,a[v.dispatchPropertyName]))&&!(a.$flags&2)&&b>>>0===b&&b<a.length)return a[b]=c
return J.bj(a).p(a,b,c)},
o_(a,b){return J.bj(a).E(a,b)},
qQ(a,b){return J.nM(a).eA(a,b)},
qR(a){return J.nN(a).eB(a)},
cE(a,b,c){return J.nN(a).eC(a,b,c)},
qS(a,b){return J.nM(a).i7(a,b)},
qT(a,b){return J.vg(a).ab(a,b)},
qU(a,b){return J.au(a).a5(a,b)},
hM(a,b){return J.bj(a).M(a,b)},
qV(a){return J.nN(a).gaa(a)},
av(a){return J.cB(a).gF(a)},
mU(a){return J.au(a).gv(a)},
qW(a){return J.au(a).gao(a)},
ae(a){return J.bj(a).gt(a)},
aw(a){return J.au(a).gk(a)},
qX(a){return J.cB(a).gS(a)},
o0(a,b,c){return J.bj(a).aR(a,b,c)},
qY(a,b,c,d,e){return J.bj(a).H(a,b,c,d,e)},
hN(a,b){return J.bj(a).ad(a,b)},
qZ(a,b){return J.nM(a).A(a,b)},
r_(a,b){return J.bj(a).f2(a,b)},
r0(a){return J.bj(a).f5(a)},
bl(a){return J.cB(a).i(a)},
fl:function fl(){},
fo:function fo(){},
dL:function dL(){},
P:function P(){},
bv:function bv(){},
fL:function fL(){},
ce:function ce(){},
ax:function ax(){},
ai:function ai(){},
cL:function cL(){},
t:function t(a){this.$ti=a},
fn:function fn(){},
iY:function iY(a){this.$ti=a},
cG:function cG(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
cK:function cK(){},
dK:function dK(){},
fp:function fp(){},
bu:function bu(){}},A={n4:function n4(){},
o9(a,b,c){if(t.O.b(a))return new A.eh(a,b.h("@<0>").X(c).h("eh<1,2>"))
return new A.bN(a,b.h("@<0>").X(c).h("bN<1,2>"))},
ot(a){return new A.c_("Field '"+a+"' has been assigned during initialization.")},
ou(a){return new A.c_("Field '"+a+"' has not been initialized.")},
rE(a){return new A.c_("Field '"+a+"' has already been initialized.")},
mA(a){var s,r=a^48
if(r<=9)return r
s=a|32
if(97<=s&&s<=102)return s-87
return-1},
bA(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
nh(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
cx(a,b,c){return a},
nQ(a){var s,r
for(s=$.cv.length,r=0;r<s;++r)if(a===$.cv[r])return!0
return!1},
e3(a,b,c,d){A.ap(b,"start")
if(c!=null){A.ap(c,"end")
if(b>c)A.C(A.S(b,0,c,"start",null))}return new A.cc(a,b,c,d.h("cc<0>"))},
rI(a,b,c,d){if(t.O.b(a))return new A.bT(a,b,c.h("@<0>").X(d).h("bT<1,2>"))
return new A.ba(a,b,c.h("@<0>").X(d).h("ba<1,2>"))},
oP(a,b,c){var s="count"
if(t.O.b(a)){A.hO(b,s)
A.ap(b,s)
return new A.cH(a,b,c.h("cH<0>"))}A.hO(b,s)
A.ap(b,s)
return new A.bc(a,b,c.h("bc<0>"))},
fm(){return new A.b0("No element")},
on(){return new A.b0("Too few elements")},
bH:function bH(){},
f5:function f5(a,b){this.a=a
this.$ti=b},
bN:function bN(a,b){this.a=a
this.$ti=b},
eh:function eh(a,b){this.a=a
this.$ti=b},
ee:function ee(){},
bO:function bO(a,b){this.a=a
this.$ti=b},
c_:function c_(a){this.a=a},
f6:function f6(a){this.a=a},
mH:function mH(){},
jo:function jo(){},
p:function p(){},
a7:function a7(){},
cc:function cc(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.$ti=d},
cO:function cO(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
ba:function ba(a,b,c){this.a=a
this.b=b
this.$ti=c},
bT:function bT(a,b,c){this.a=a
this.b=b
this.$ti=c},
fy:function fy(a,b,c){var _=this
_.a=null
_.b=a
_.c=b
_.$ti=c},
aa:function aa(a,b,c){this.a=a
this.b=b
this.$ti=c},
e8:function e8(a,b,c){this.a=a
this.b=b
this.$ti=c},
e9:function e9(a,b){this.a=a
this.b=b},
bc:function bc(a,b,c){this.a=a
this.b=b
this.$ti=c},
cH:function cH(a,b,c){this.a=a
this.b=b
this.$ti=c},
fV:function fV(a,b){this.a=a
this.b=b},
bU:function bU(a){this.$ti=a},
fd:function fd(){},
ea:function ea(a,b){this.a=a
this.$ti=b},
h9:function h9(a,b){this.a=a
this.$ti=b},
dG:function dG(){},
h0:function h0(){},
d0:function d0(){},
dX:function dX(a,b){this.a=a
this.$ti=b},
eL:function eL(){},
qj(a){var s=v.mangledGlobalNames[a]
if(s!=null)return s
return"minified:"+a},
q9(a,b){var s
if(b!=null){s=b.x
if(s!=null)return s}return t.aU.b(a)},
y(a){var s
if(typeof a=="string")return a
if(typeof a=="number"){if(a!==0)return""+a}else if(!0===a)return"true"
else if(!1===a)return"false"
else if(a==null)return"null"
s=J.bl(a)
return s},
dW(a){var s,r=$.oA
if(r==null)r=$.oA=Symbol("identityHashCode")
s=a[r]
if(s==null){s=Math.random()*0x3fffffff|0
a[r]=s}return s},
oH(a,b){var s,r=/^\s*[+-]?((0x[a-f0-9]+)|(\d+)|([a-z0-9]+))\s*$/i.exec(a)
if(r==null)return null
s=r[3]
if(s!=null)return parseInt(a,10)
if(r[2]!=null)return parseInt(a,16)
return null},
fM(a){var s,r,q,p
if(a instanceof A.l)return A.aC(A.bL(a),null)
s=J.cB(a)
if(s===B.b_||s===B.b1||t.ak.b(a)){r=B.L(a)
if(r!=="Object"&&r!=="")return r
q=a.constructor
if(typeof q=="function"){p=q.name
if(typeof p=="string"&&p!=="Object"&&p!=="")return p}}return A.aC(A.bL(a),null)},
oI(a){var s,r,q
if(a==null||typeof a=="number"||A.dj(a))return J.bl(a)
if(typeof a=="string")return JSON.stringify(a)
if(a instanceof A.bQ)return a.i(0)
if(a instanceof A.eu)return a.ev(!0)
s=$.qL()
for(r=0;r<1;++r){q=s[r].ja(a)
if(q!=null)return q}return"Instance of '"+A.fM(a)+"'"},
rX(){if(!!self.location)return self.location.href
return null},
oz(a){var s,r,q,p,o=a.length
if(o<=500)return String.fromCharCode.apply(null,a)
for(s="",r=0;r<o;r=q){q=r+500
p=q<o?q:o
s+=String.fromCharCode.apply(null,a.slice(r,p))}return s},
t0(a){var s,r,q,p=A.n([],t.t)
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.R)(a),++r){q=a[r]
if(!A.ct(q))throw A.a(A.dq(q))
if(q<=65535)p.push(q)
else if(q<=1114111){p.push(55296+(B.b.I(q-65536,10)&1023))
p.push(56320+(q&1023))}else throw A.a(A.dq(q))}return A.oz(p)},
oJ(a){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(!A.ct(q))throw A.a(A.dq(q))
if(q<0)throw A.a(A.dq(q))
if(q>65535)return A.t0(a)}return A.oz(a)},
t1(a,b,c){var s,r,q,p
if(c<=500&&b===0&&c===a.length)return String.fromCharCode.apply(null,a)
for(s=b,r="";s<c;s=q){q=s+500
p=q<c?q:c
r+=String.fromCharCode.apply(null,a.subarray(s,p))}return r},
aX(a){var s
if(0<=a){if(a<=65535)return String.fromCharCode(a)
if(a<=1114111){s=a-65536
return String.fromCharCode((B.b.I(s,10)|55296)>>>0,s&1023|56320)}}throw A.a(A.S(a,0,1114111,null,null))},
aj(a){if(a.date===void 0)a.date=new Date(a.a)
return a.date},
oG(a){return a.c?A.aj(a).getUTCFullYear()+0:A.aj(a).getFullYear()+0},
oE(a){return a.c?A.aj(a).getUTCMonth()+1:A.aj(a).getMonth()+1},
oB(a){return a.c?A.aj(a).getUTCDate()+0:A.aj(a).getDate()+0},
oC(a){return a.c?A.aj(a).getUTCHours()+0:A.aj(a).getHours()+0},
oD(a){return a.c?A.aj(a).getUTCMinutes()+0:A.aj(a).getMinutes()+0},
oF(a){return a.c?A.aj(a).getUTCSeconds()+0:A.aj(a).getSeconds()+0},
rZ(a){return a.c?A.aj(a).getUTCMilliseconds()+0:A.aj(a).getMilliseconds()+0},
t_(a){return B.b.a7((a.c?A.aj(a).getUTCDay()+0:A.aj(a).getDay()+0)+6,7)+1},
rY(a){var s=a.$thrownJsError
if(s==null)return null
return A.al(s)},
jd(a,b){var s
if(a.$thrownJsError==null){s=new Error()
A.V(a,s)
a.$thrownJsError=s
s.stack=b.i(0)}},
eS(a,b){var s,r="index"
if(!A.ct(b))return new A.aN(!0,b,r,null)
s=J.aw(a)
if(b<0||b>=s)return A.fh(b,s,a,null,r)
return A.nb(b,r)},
vb(a,b,c){if(a>c)return A.S(a,0,c,"start",null)
if(b!=null)if(b<a||b>c)return A.S(b,a,c,"end",null)
return new A.aN(!0,b,"end",null)},
dq(a){return new A.aN(!0,a,null,null)},
a(a){return A.V(a,new Error())},
V(a,b){var s
if(a==null)a=new A.bd()
b.dartException=a
s=A.vZ
if("defineProperty" in Object){Object.defineProperty(b,"message",{get:s})
b.name=""}else b.toString=s
return b},
vZ(){return J.bl(this.dartException)},
C(a,b){throw A.V(a,b==null?new Error():b)},
v(a,b,c){var s
if(b==null)b=0
if(c==null)c=0
s=Error()
A.C(A.un(a,b,c),s)},
un(a,b,c){var s,r,q,p,o,n,m,l,k
if(typeof b=="string")s=b
else{r="[]=;add;removeWhere;retainWhere;removeRange;setRange;setInt8;setInt16;setInt32;setUint8;setUint16;setUint32;setFloat32;setFloat64".split(";")
q=r.length
p=b
if(p>q){c=p/q|0
p%=q}s=r[p]}o=typeof c=="string"?c:"modify;remove from;add to".split(";")[c]
n=t.j.b(a)?"list":"ByteData"
m=a.$flags|0
l="a "
if((m&4)!==0)k="constant "
else if((m&2)!==0){k="unmodifiable "
l="an "}else k=(m&1)!==0?"fixed-length ":""
return new A.e4("'"+s+"': Cannot "+o+" "+l+k+n)},
R(a){throw A.a(A.a5(a))},
be(a){var s,r,q,p,o,n
a=A.qf(a.replace(String({}),"$receiver$"))
s=a.match(/\\\$[a-zA-Z]+\\\$/g)
if(s==null)s=A.n([],t.s)
r=s.indexOf("\\$arguments\\$")
q=s.indexOf("\\$argumentsExpr\\$")
p=s.indexOf("\\$expr\\$")
o=s.indexOf("\\$method\\$")
n=s.indexOf("\\$receiver\\$")
return new A.jP(a.replace(new RegExp("\\\\\\$arguments\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$argumentsExpr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$expr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$method\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$receiver\\\\\\$","g"),"((?:x|[^x])*)"),r,q,p,o,n)},
jQ(a){return function($expr$){var $argumentsExpr$="$arguments$"
try{$expr$.$method$($argumentsExpr$)}catch(s){return s.message}}(a)},
oV(a){return function($expr$){try{$expr$.$method$}catch(s){return s.message}}(a)},
n5(a,b){var s=b==null,r=s?null:b.method
return new A.fs(a,r,s?null:b.receiver)},
W(a){if(a==null)return new A.fI(a)
if(a instanceof A.dE)return A.bM(a,a.a)
if(typeof a!=="object")return a
if("dartException" in a)return A.bM(a,a.dartException)
return A.uZ(a)},
bM(a,b){if(t.C.b(b))if(b.$thrownJsError==null)b.$thrownJsError=a
return b},
uZ(a){var s,r,q,p,o,n,m,l,k,j,i,h,g
if(!("message" in a))return a
s=a.message
if("number" in a&&typeof a.number=="number"){r=a.number
q=r&65535
if((B.b.I(r,16)&8191)===10)switch(q){case 438:return A.bM(a,A.n5(A.y(s)+" (Error "+q+")",null))
case 445:case 5007:A.y(s)
return A.bM(a,new A.dU())}}if(a instanceof TypeError){p=$.qp()
o=$.qq()
n=$.qr()
m=$.qs()
l=$.qv()
k=$.qw()
j=$.qu()
$.qt()
i=$.qy()
h=$.qx()
g=p.af(s)
if(g!=null)return A.bM(a,A.n5(s,g))
else{g=o.af(s)
if(g!=null){g.method="call"
return A.bM(a,A.n5(s,g))}else if(n.af(s)!=null||m.af(s)!=null||l.af(s)!=null||k.af(s)!=null||j.af(s)!=null||m.af(s)!=null||i.af(s)!=null||h.af(s)!=null)return A.bM(a,new A.dU())}return A.bM(a,new A.h_(typeof s=="string"?s:""))}if(a instanceof RangeError){if(typeof s=="string"&&s.indexOf("call stack")!==-1)return new A.e0()
s=function(b){try{return String(b)}catch(f){}return null}(a)
return A.bM(a,new A.aN(!1,null,null,typeof s=="string"?s.replace(/^RangeError:\s*/,""):s))}if(typeof InternalError=="function"&&a instanceof InternalError)if(typeof s=="string"&&s==="too much recursion")return new A.e0()
return a},
al(a){var s
if(a instanceof A.dE)return a.b
if(a==null)return new A.ey(a)
s=a.$cachedTrace
if(s!=null)return s
s=new A.ey(a)
if(typeof a==="object")a.$cachedTrace=s
return s},
mI(a){if(a==null)return J.av(a)
if(typeof a=="object")return A.dW(a)
return J.av(a)},
vf(a,b){var s,r,q,p=a.length
for(s=0;s<p;s=q){r=s+1
q=r+1
b.p(0,a[s],a[r])}return b},
ux(a,b,c,d,e,f){switch(b){case 0:return a.$0()
case 1:return a.$1(c)
case 2:return a.$2(c,d)
case 3:return a.$3(c,d,e)
case 4:return a.$4(c,d,e,f)}throw A.a(A.mX("Unsupported number of arguments for wrapped closure"))},
cz(a,b){var s
if(a==null)return null
s=a.$identity
if(!!s)return s
s=A.v6(a,b)
a.$identity=s
return s},
v6(a,b){var s
switch(b){case 0:s=a.$0
break
case 1:s=a.$1
break
case 2:s=a.$2
break
case 3:s=a.$3
break
case 4:s=a.$4
break
default:s=null}if(s!=null)return s.bind(a)
return function(c,d,e){return function(f,g,h,i){return e(c,d,f,g,h,i)}}(a,b,A.ux)},
rb(a2){var s,r,q,p,o,n,m,l,k,j,i=a2.co,h=a2.iS,g=a2.iI,f=a2.nDA,e=a2.aI,d=a2.fs,c=a2.cs,b=d[0],a=c[0],a0=i[b],a1=a2.fT
a1.toString
s=h?Object.create(new A.jy().constructor.prototype):Object.create(new A.dw(null,null).constructor.prototype)
s.$initialize=s.constructor
r=h?function static_tear_off(){this.$initialize()}:function tear_off(a3,a4){this.$initialize(a3,a4)}
s.constructor=r
r.prototype=s
s.$_name=b
s.$_target=a0
q=!h
if(q)p=A.ob(b,a0,g,f)
else{s.$static_name=b
p=a0}s.$S=A.r7(a1,h,g)
s[a]=p
for(o=p,n=1;n<d.length;++n){m=d[n]
if(typeof m=="string"){l=i[m]
k=m
m=l}else k=""
j=c[n]
if(j!=null){if(q)m=A.ob(k,m,g,f)
s[j]=m}if(n===e)o=m}s.$C=o
s.$R=a2.rC
s.$D=a2.dV
return r},
r7(a,b,c){if(typeof a=="number")return a
if(typeof a=="string"){if(b)throw A.a("Cannot compute signature for static tearoff.")
return function(d,e){return function(){return e(this,d)}}(a,A.r4)}throw A.a("Error in functionType of tearoff")},
r8(a,b,c,d){var s=A.o8
switch(b?-1:a){case 0:return function(e,f){return function(){return f(this)[e]()}}(c,s)
case 1:return function(e,f){return function(g){return f(this)[e](g)}}(c,s)
case 2:return function(e,f){return function(g,h){return f(this)[e](g,h)}}(c,s)
case 3:return function(e,f){return function(g,h,i){return f(this)[e](g,h,i)}}(c,s)
case 4:return function(e,f){return function(g,h,i,j){return f(this)[e](g,h,i,j)}}(c,s)
case 5:return function(e,f){return function(g,h,i,j,k){return f(this)[e](g,h,i,j,k)}}(c,s)
default:return function(e,f){return function(){return e.apply(f(this),arguments)}}(d,s)}},
ob(a,b,c,d){if(c)return A.ra(a,b,d)
return A.r8(b.length,d,a,b)},
r9(a,b,c,d){var s=A.o8,r=A.r5
switch(b?-1:a){case 0:throw A.a(new A.fR("Intercepted function with no arguments."))
case 1:return function(e,f,g){return function(){return f(this)[e](g(this))}}(c,r,s)
case 2:return function(e,f,g){return function(h){return f(this)[e](g(this),h)}}(c,r,s)
case 3:return function(e,f,g){return function(h,i){return f(this)[e](g(this),h,i)}}(c,r,s)
case 4:return function(e,f,g){return function(h,i,j){return f(this)[e](g(this),h,i,j)}}(c,r,s)
case 5:return function(e,f,g){return function(h,i,j,k){return f(this)[e](g(this),h,i,j,k)}}(c,r,s)
case 6:return function(e,f,g){return function(h,i,j,k,l){return f(this)[e](g(this),h,i,j,k,l)}}(c,r,s)
default:return function(e,f,g){return function(){var q=[g(this)]
Array.prototype.push.apply(q,arguments)
return e.apply(f(this),q)}}(d,r,s)}},
ra(a,b,c){var s,r
if($.o6==null)$.o6=A.o5("interceptor")
if($.o7==null)$.o7=A.o5("receiver")
s=b.length
r=A.r9(s,c,a,b)
return r},
nK(a){return A.rb(a)},
r4(a,b){return A.eG(v.typeUniverse,A.bL(a.a),b)},
o8(a){return a.a},
r5(a){return a.b},
o5(a){var s,r,q,p=new A.dw("receiver","interceptor"),o=Object.getOwnPropertyNames(p)
o.$flags=1
s=o
for(o=s.length,r=0;r<o;++r){q=s[r]
if(p[q]===a)return q}throw A.a(A.M("Field name "+a+" not found.",null))},
vh(a){return v.getIsolateTag(a)},
w0(a,b){var s=$.q
if(s===B.e)return a
return s.eD(a,b)},
qg(){return v.G},
wS(a,b,c){Object.defineProperty(a,b,{value:c,enumerable:false,writable:true,configurable:true})},
vq(a){var s,r,q,p,o,n=$.q7.$1(a),m=$.mx[n]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.mE[n]
if(s!=null)return s
r=v.interceptorsByTag[n]
if(r==null){q=$.q3.$2(a,n)
if(q!=null){m=$.mx[q]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.mE[q]
if(s!=null)return s
r=v.interceptorsByTag[q]
n=q}}if(r==null)return null
s=r.prototype
p=n[0]
if(p==="!"){m=A.mG(s)
$.mx[n]=m
Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}if(p==="~"){$.mE[n]=s
return s}if(p==="-"){o=A.mG(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}if(p==="+")return A.qc(a,s)
if(p==="*")throw A.a(A.nl(n))
if(v.leafTags[n]===true){o=A.mG(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}else return A.qc(a,s)},
qc(a,b){var s=Object.getPrototypeOf(a)
Object.defineProperty(s,v.dispatchPropertyName,{value:J.nR(b,s,null,null),enumerable:false,writable:true,configurable:true})
return b},
mG(a){return J.nR(a,!1,null,!!a.$iay)},
vs(a,b,c){var s=b.prototype
if(v.leafTags[a]===true)return A.mG(s)
else return J.nR(s,c,null,null)},
vl(){if(!0===$.nP)return
$.nP=!0
A.vm()},
vm(){var s,r,q,p,o,n,m,l
$.mx=Object.create(null)
$.mE=Object.create(null)
A.vk()
s=v.interceptorsByTag
r=Object.getOwnPropertyNames(s)
if(typeof window!="undefined"){window
q=function(){}
for(p=0;p<r.length;++p){o=r[p]
n=$.qe.$1(o)
if(n!=null){m=A.vs(o,s[o],n)
if(m!=null){Object.defineProperty(n,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
q.prototype=n}}}}for(p=0;p<r.length;++p){o=r[p]
if(/^[A-Za-z_]/.test(o)){l=s[o]
s["!"+o]=l
s["~"+o]=l
s["-"+o]=l
s["+"+o]=l
s["*"+o]=l}}},
vk(){var s,r,q,p,o,n,m=B.aI()
m=A.dp(B.aJ,A.dp(B.aK,A.dp(B.M,A.dp(B.M,A.dp(B.aL,A.dp(B.aM,A.dp(B.aN(B.L),m)))))))
if(typeof dartNativeDispatchHooksTransformer!="undefined"){s=dartNativeDispatchHooksTransformer
if(typeof s=="function")s=[s]
if(Array.isArray(s))for(r=0;r<s.length;++r){q=s[r]
if(typeof q=="function")m=q(m)||m}}p=m.getTag
o=m.getUnknownTag
n=m.prototypeForTag
$.q7=new A.mB(p)
$.q3=new A.mC(o)
$.qe=new A.mD(n)},
dp(a,b){return a(b)||b},
v9(a,b){var s=b.length,r=v.rttc[""+s+";"+a]
if(r==null)return null
if(s===0)return r
if(s===r.length)return r.apply(null,b)
return r(b)},
or(a,b,c,d,e,f){var s=b?"m":"",r=c?"":"i",q=d?"u":"",p=e?"s":"",o=function(g,h){try{return new RegExp(g,h)}catch(n){return n}}(a,s+r+q+p+f)
if(o instanceof RegExp)return o
throw A.a(A.a3("Illegal RegExp pattern ("+String(o)+")",a,null))},
vV(a,b,c){var s
if(typeof b=="string")return a.indexOf(b,c)>=0
else if(b instanceof A.fr){s=B.a.T(a,c)
return b.b.test(s)}else return!J.qQ(b,B.a.T(a,c)).gv(0)},
vd(a){if(a.indexOf("$",0)>=0)return a.replace(/\$/g,"$$$$")
return a},
qf(a){if(/[[\]{}()*+?.\\^$|]/.test(a))return a.replace(/[[\]{}()*+?.\\^$|]/g,"\\$&")
return a},
vW(a,b,c){var s=A.vX(a,b,c)
return s},
vX(a,b,c){var s,r,q
if(b===""){if(a==="")return c
s=a.length
for(r=c,q=0;q<s;++q)r=r+a[q]+c
return r.charCodeAt(0)==0?r:r}if(a.indexOf(b,0)<0)return a
if(a.length<500||c.indexOf("$",0)>=0)return a.split(b).join(c)
return a.replace(new RegExp(A.qf(b),"g"),A.vd(c))},
aB:function aB(a,b){this.a=a
this.b=b},
ev:function ev(a,b){this.a=a
this.b=b},
ew:function ew(a,b){this.a=a
this.b=b},
cn:function cn(a,b){this.a=a
this.b=b},
dz:function dz(){},
dA:function dA(a,b,c){this.a=a
this.b=b
this.$ti=c},
el:function el(a,b){this.a=a
this.$ti=b},
hs:function hs(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
dY:function dY(){},
jP:function jP(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
dU:function dU(){},
fs:function fs(a,b,c){this.a=a
this.b=b
this.c=c},
h_:function h_(a){this.a=a},
fI:function fI(a){this.a=a},
dE:function dE(a,b){this.a=a
this.b=b},
ey:function ey(a){this.a=a
this.b=null},
bQ:function bQ(){},
i_:function i_(){},
i0:function i0(){},
jF:function jF(){},
jy:function jy(){},
dw:function dw(a,b){this.a=a
this.b=b},
fR:function fR(a){this.a=a},
bZ:function bZ(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
iZ:function iZ(a){this.a=a},
j0:function j0(a,b){var _=this
_.a=a
_.b=b
_.d=_.c=null},
b8:function b8(a,b){this.a=a
this.$ti=b},
fx:function fx(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=null},
cM:function cM(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=null},
dN:function dN(a,b){this.a=a
this.$ti=b},
fw:function fw(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
mB:function mB(a){this.a=a},
mC:function mC(a){this.a=a},
mD:function mD(a){this.a=a},
eu:function eu(){},
hw:function hw(){},
fr:function fr(a,b){var _=this
_.a=a
_.b=b
_.e=_.d=_.c=null},
en:function en(a){this.b=a},
ha:function ha(a,b,c){this.a=a
this.b=b
this.c=c},
ki:function ki(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=null},
fY:function fY(a,b){this.a=a
this.c=b},
hD:function hD(a,b,c){this.a=a
this.b=b
this.c=c},
m4:function m4(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=null},
vY(a){throw A.V(A.ot(a),new Error())},
O(){throw A.V(A.ou(""),new Error())},
qi(){throw A.V(A.rE(""),new Error())},
qh(){throw A.V(A.ot(""),new Error())},
pc(){var s=new A.he("")
return s.b=s},
ks(a){var s=new A.he(a)
return s.b=s},
he:function he(a){this.a=a
this.b=null},
uk(a){return a},
eM(a,b,c){},
pK(a){return a},
ow(a,b,c){var s
A.eM(a,b,c)
s=new DataView(a,b)
return s},
bw(a,b,c){A.eM(a,b,c)
c=B.b.K(a.byteLength-b,4)
return new Int32Array(a,b,c)},
rT(a){return new Int8Array(a)},
rU(a,b,c){A.eM(a,b,c)
return new Uint32Array(a,b,c)},
ox(a){return new Uint8Array(a)},
aF(a,b,c){A.eM(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
bi(a,b,c){if(a>>>0!==a||a>=c)throw A.a(A.eS(b,a))},
ul(a,b,c){var s
if(!(a>>>0!==a))s=b>>>0!==b||a>b||b>c
else s=!0
if(s)throw A.a(A.vb(a,b,c))
return b},
cP:function cP(){},
c1:function c1(){},
dR:function dR(){},
hH:function hH(a){this.a=a},
c2:function c2(){},
cR:function cR(){},
bx:function bx(){},
aA:function aA(){},
fA:function fA(){},
fB:function fB(){},
fC:function fC(){},
cQ:function cQ(){},
fD:function fD(){},
fE:function fE(){},
fF:function fF(){},
dS:function dS(){},
c3:function c3(){},
ep:function ep(){},
eq:function eq(){},
er:function er(){},
es:function es(){},
nc(a,b){var s=b.c
return s==null?b.c=A.eE(a,"K",[b.x]):s},
oN(a){var s=a.w
if(s===6||s===7)return A.oN(a.x)
return s===11||s===12},
ta(a){return a.as},
E(a){return A.m8(v.typeUniverse,a,!1)},
cu(a1,a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=a2.w
switch(a0){case 5:case 1:case 2:case 3:case 4:return a2
case 6:s=a2.x
r=A.cu(a1,s,a3,a4)
if(r===s)return a2
return A.pp(a1,r,!0)
case 7:s=a2.x
r=A.cu(a1,s,a3,a4)
if(r===s)return a2
return A.po(a1,r,!0)
case 8:q=a2.y
p=A.dn(a1,q,a3,a4)
if(p===q)return a2
return A.eE(a1,a2.x,p)
case 9:o=a2.x
n=A.cu(a1,o,a3,a4)
m=a2.y
l=A.dn(a1,m,a3,a4)
if(n===o&&l===m)return a2
return A.nx(a1,n,l)
case 10:k=a2.x
j=a2.y
i=A.dn(a1,j,a3,a4)
if(i===j)return a2
return A.pq(a1,k,i)
case 11:h=a2.x
g=A.cu(a1,h,a3,a4)
f=a2.y
e=A.uV(a1,f,a3,a4)
if(g===h&&e===f)return a2
return A.pn(a1,g,e)
case 12:d=a2.y
a4+=d.length
c=A.dn(a1,d,a3,a4)
o=a2.x
n=A.cu(a1,o,a3,a4)
if(c===d&&n===o)return a2
return A.ny(a1,n,c,!0)
case 13:b=a2.x
if(b<a4)return a2
a=a3[b-a4]
if(a==null)return a2
return a
default:throw A.a(A.eZ("Attempted to substitute unexpected RTI kind "+a0))}},
dn(a,b,c,d){var s,r,q,p,o=b.length,n=A.md(o)
for(s=!1,r=0;r<o;++r){q=b[r]
p=A.cu(a,q,c,d)
if(p!==q)s=!0
n[r]=p}return s?n:b},
uW(a,b,c,d){var s,r,q,p,o,n,m=b.length,l=A.md(m)
for(s=!1,r=0;r<m;r+=3){q=b[r]
p=b[r+1]
o=b[r+2]
n=A.cu(a,o,c,d)
if(n!==o)s=!0
l.splice(r,3,q,p,n)}return s?l:b},
uV(a,b,c,d){var s,r=b.a,q=A.dn(a,r,c,d),p=b.b,o=A.dn(a,p,c,d),n=b.c,m=A.uW(a,n,c,d)
if(q===r&&o===p&&m===n)return b
s=new A.hk()
s.a=q
s.b=o
s.c=m
return s},
n(a,b){a[v.arrayRti]=b
return a},
q5(a){var s=a.$S
if(s!=null){if(typeof s=="number")return A.vj(s)
return a.$S()}return null},
vn(a,b){var s
if(A.oN(b))if(a instanceof A.bQ){s=A.q5(a)
if(s!=null)return s}return A.bL(a)},
bL(a){if(a instanceof A.l)return A.D(a)
if(Array.isArray(a))return A.ac(a)
return A.nG(J.cB(a))},
ac(a){var s=a[v.arrayRti],r=t.gn
if(s==null)return r
if(s.constructor!==r.constructor)return r
return s},
D(a){var s=a.$ti
return s!=null?s:A.nG(a)},
nG(a){var s=a.constructor,r=s.$ccache
if(r!=null)return r
return A.uv(a,s)},
uv(a,b){var s=a instanceof A.bQ?Object.getPrototypeOf(Object.getPrototypeOf(a)).constructor:b,r=A.tU(v.typeUniverse,s.name)
b.$ccache=r
return r},
vj(a){var s,r=v.types,q=r[a]
if(typeof q=="string"){s=A.m8(v.typeUniverse,q,!1)
r[a]=s
return s}return q},
vi(a){return A.cA(A.D(a))},
nJ(a){var s
if(a instanceof A.eu)return A.ve(a.$r,a.ed())
s=a instanceof A.bQ?A.q5(a):null
if(s!=null)return s
if(t.dm.b(a))return J.qX(a).a
if(Array.isArray(a))return A.ac(a)
return A.bL(a)},
cA(a){var s=a.r
return s==null?a.r=new A.m7(a):s},
ve(a,b){var s,r,q=b,p=q.length
if(p===0)return t.bQ
s=A.eG(v.typeUniverse,A.nJ(q[0]),"@<0>")
for(r=1;r<p;++r)s=A.pr(v.typeUniverse,s,A.nJ(q[r]))
return A.eG(v.typeUniverse,s,a)},
aS(a){return A.cA(A.m8(v.typeUniverse,a,!1))},
uu(a){var s=this
s.b=A.uT(s)
return s.b(a)},
uT(a){var s,r,q,p
if(a===t.K)return A.uD
if(A.cC(a))return A.uH
s=a.w
if(s===6)return A.us
if(s===1)return A.pS
if(s===7)return A.uy
r=A.uS(a)
if(r!=null)return r
if(s===8){q=a.x
if(a.y.every(A.cC)){a.f="$i"+q
if(q==="u")return A.uB
if(a===t.m)return A.uA
return A.uG}}else if(s===10){p=A.v9(a.x,a.y)
return p==null?A.pS:p}return A.uq},
uS(a){if(a.w===8){if(a===t.S)return A.ct
if(a===t.i||a===t.o)return A.uC
if(a===t.N)return A.uF
if(a===t.y)return A.dj}return null},
ut(a){var s=this,r=A.up
if(A.cC(s))r=A.ua
else if(s===t.K)r=A.u9
else if(A.dr(s)){r=A.ur
if(s===t.I)r=A.u6
else if(s===t.dk)r=A.pH
else if(s===t.fQ)r=A.nD
else if(s===t.cg)r=A.u8
else if(s===t.cD)r=A.nE
else if(s===t.A)r=A.pG}else if(s===t.S)r=A.r
else if(s===t.N)r=A.ah
else if(s===t.y)r=A.aR
else if(s===t.o)r=A.u7
else if(s===t.i)r=A.z
else if(s===t.m)r=A.a9
s.a=r
return s.a(a)},
uq(a){var s=this
if(a==null)return A.dr(s)
return A.vp(v.typeUniverse,A.vn(a,s),s)},
us(a){if(a==null)return!0
return this.x.b(a)},
uG(a){var s,r=this
if(a==null)return A.dr(r)
s=r.f
if(a instanceof A.l)return!!a[s]
return!!J.cB(a)[s]},
uB(a){var s,r=this
if(a==null)return A.dr(r)
if(typeof a!="object")return!1
if(Array.isArray(a))return!0
s=r.f
if(a instanceof A.l)return!!a[s]
return!!J.cB(a)[s]},
uA(a){var s=this
if(a==null)return!1
if(typeof a=="object"){if(a instanceof A.l)return!!a[s.f]
return!0}if(typeof a=="function")return!0
return!1},
pR(a){if(typeof a=="object"){if(a instanceof A.l)return t.m.b(a)
return!0}if(typeof a=="function")return!0
return!1},
up(a){var s=this
if(a==null){if(A.dr(s))return a}else if(s.b(a))return a
throw A.V(A.pL(a,s),new Error())},
ur(a){var s=this
if(a==null||s.b(a))return a
throw A.V(A.pL(a,s),new Error())},
pL(a,b){return new A.eC("TypeError: "+A.pe(a,A.aC(b,null)))},
pe(a,b){return A.dD(a)+": type '"+A.aC(A.nJ(a),null)+"' is not a subtype of type '"+b+"'"},
aJ(a,b){return new A.eC("TypeError: "+A.pe(a,b))},
uy(a){var s=this
return s.x.b(a)||A.nc(v.typeUniverse,s).b(a)},
uD(a){return a!=null},
u9(a){if(a!=null)return a
throw A.V(A.aJ(a,"Object"),new Error())},
uH(a){return!0},
ua(a){return a},
pS(a){return!1},
dj(a){return!0===a||!1===a},
aR(a){if(!0===a)return!0
if(!1===a)return!1
throw A.V(A.aJ(a,"bool"),new Error())},
nD(a){if(!0===a)return!0
if(!1===a)return!1
if(a==null)return a
throw A.V(A.aJ(a,"bool?"),new Error())},
z(a){if(typeof a=="number")return a
throw A.V(A.aJ(a,"double"),new Error())},
nE(a){if(typeof a=="number")return a
if(a==null)return a
throw A.V(A.aJ(a,"double?"),new Error())},
ct(a){return typeof a=="number"&&Math.floor(a)===a},
r(a){if(typeof a=="number"&&Math.floor(a)===a)return a
throw A.V(A.aJ(a,"int"),new Error())},
u6(a){if(typeof a=="number"&&Math.floor(a)===a)return a
if(a==null)return a
throw A.V(A.aJ(a,"int?"),new Error())},
uC(a){return typeof a=="number"},
u7(a){if(typeof a=="number")return a
throw A.V(A.aJ(a,"num"),new Error())},
u8(a){if(typeof a=="number")return a
if(a==null)return a
throw A.V(A.aJ(a,"num?"),new Error())},
uF(a){return typeof a=="string"},
ah(a){if(typeof a=="string")return a
throw A.V(A.aJ(a,"String"),new Error())},
pH(a){if(typeof a=="string")return a
if(a==null)return a
throw A.V(A.aJ(a,"String?"),new Error())},
a9(a){if(A.pR(a))return a
throw A.V(A.aJ(a,"JSObject"),new Error())},
pG(a){if(a==null)return a
if(A.pR(a))return a
throw A.V(A.aJ(a,"JSObject?"),new Error())},
pY(a,b){var s,r,q
for(s="",r="",q=0;q<a.length;++q,r=", ")s+=r+A.aC(a[q],b)
return s},
uP(a,b){var s,r,q,p,o,n,m=a.x,l=a.y
if(""===m)return"("+A.pY(l,b)+")"
s=l.length
r=m.split(",")
q=r.length-s
for(p="(",o="",n=0;n<s;++n,o=", "){p+=o
if(q===0)p+="{"
p+=A.aC(l[n],b)
if(q>=0)p+=" "+r[q];++q}return p+"})"},
pO(a1,a2,a3){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a=", ",a0=null
if(a3!=null){s=a3.length
if(a2==null)a2=A.n([],t.s)
else a0=a2.length
r=a2.length
for(q=s;q>0;--q)a2.push("T"+(r+q))
for(p=t.X,o="<",n="",q=0;q<s;++q,n=a){o=o+n+a2[a2.length-1-q]
m=a3[q]
l=m.w
if(!(l===2||l===3||l===4||l===5||m===p))o+=" extends "+A.aC(m,a2)}o+=">"}else o=""
p=a1.x
k=a1.y
j=k.a
i=j.length
h=k.b
g=h.length
f=k.c
e=f.length
d=A.aC(p,a2)
for(c="",b="",q=0;q<i;++q,b=a)c+=b+A.aC(j[q],a2)
if(g>0){c+=b+"["
for(b="",q=0;q<g;++q,b=a)c+=b+A.aC(h[q],a2)
c+="]"}if(e>0){c+=b+"{"
for(b="",q=0;q<e;q+=3,b=a){c+=b
if(f[q+1])c+="required "
c+=A.aC(f[q+2],a2)+" "+f[q]}c+="}"}if(a0!=null){a2.toString
a2.length=a0}return o+"("+c+") => "+d},
aC(a,b){var s,r,q,p,o,n,m=a.w
if(m===5)return"erased"
if(m===2)return"dynamic"
if(m===3)return"void"
if(m===1)return"Never"
if(m===4)return"any"
if(m===6){s=a.x
r=A.aC(s,b)
q=s.w
return(q===11||q===12?"("+r+")":r)+"?"}if(m===7)return"FutureOr<"+A.aC(a.x,b)+">"
if(m===8){p=A.uY(a.x)
o=a.y
return o.length>0?p+("<"+A.pY(o,b)+">"):p}if(m===10)return A.uP(a,b)
if(m===11)return A.pO(a,b,null)
if(m===12)return A.pO(a.x,b,a.y)
if(m===13){n=a.x
return b[b.length-1-n]}return"?"},
uY(a){var s=v.mangledGlobalNames[a]
if(s!=null)return s
return"minified:"+a},
tV(a,b){var s=a.tR[b]
while(typeof s=="string")s=a.tR[s]
return s},
tU(a,b){var s,r,q,p,o,n=a.eT,m=n[b]
if(m==null)return A.m8(a,b,!1)
else if(typeof m=="number"){s=m
r=A.eF(a,5,"#")
q=A.md(s)
for(p=0;p<s;++p)q[p]=r
o=A.eE(a,b,q)
n[b]=o
return o}else return m},
tT(a,b){return A.pE(a.tR,b)},
tS(a,b){return A.pE(a.eT,b)},
m8(a,b,c){var s,r=a.eC,q=r.get(b)
if(q!=null)return q
s=A.pj(A.ph(a,null,b,!1))
r.set(b,s)
return s},
eG(a,b,c){var s,r,q=b.z
if(q==null)q=b.z=new Map()
s=q.get(c)
if(s!=null)return s
r=A.pj(A.ph(a,b,c,!0))
q.set(c,r)
return r},
pr(a,b,c){var s,r,q,p=b.Q
if(p==null)p=b.Q=new Map()
s=c.as
r=p.get(s)
if(r!=null)return r
q=A.nx(a,b,c.w===9?c.y:[c])
p.set(s,q)
return q},
bK(a,b){b.a=A.ut
b.b=A.uu
return b},
eF(a,b,c){var s,r,q=a.eC.get(c)
if(q!=null)return q
s=new A.aP(null,null)
s.w=b
s.as=c
r=A.bK(a,s)
a.eC.set(c,r)
return r},
pp(a,b,c){var s,r=b.as+"?",q=a.eC.get(r)
if(q!=null)return q
s=A.tQ(a,b,r,c)
a.eC.set(r,s)
return s},
tQ(a,b,c,d){var s,r,q
if(d){s=b.w
r=!0
if(!A.cC(b))if(!(b===t.P||b===t.T))if(s!==6)r=s===7&&A.dr(b.x)
if(r)return b
else if(s===1)return t.P}q=new A.aP(null,null)
q.w=6
q.x=b
q.as=c
return A.bK(a,q)},
po(a,b,c){var s,r=b.as+"/",q=a.eC.get(r)
if(q!=null)return q
s=A.tO(a,b,r,c)
a.eC.set(r,s)
return s},
tO(a,b,c,d){var s,r
if(d){s=b.w
if(A.cC(b)||b===t.K)return b
else if(s===1)return A.eE(a,"K",[b])
else if(b===t.P||b===t.T)return t.eH}r=new A.aP(null,null)
r.w=7
r.x=b
r.as=c
return A.bK(a,r)},
tR(a,b){var s,r,q=""+b+"^",p=a.eC.get(q)
if(p!=null)return p
s=new A.aP(null,null)
s.w=13
s.x=b
s.as=q
r=A.bK(a,s)
a.eC.set(q,r)
return r},
eD(a){var s,r,q,p=a.length
for(s="",r="",q=0;q<p;++q,r=",")s+=r+a[q].as
return s},
tN(a){var s,r,q,p,o,n=a.length
for(s="",r="",q=0;q<n;q+=3,r=","){p=a[q]
o=a[q+1]?"!":":"
s+=r+p+o+a[q+2].as}return s},
eE(a,b,c){var s,r,q,p=b
if(c.length>0)p+="<"+A.eD(c)+">"
s=a.eC.get(p)
if(s!=null)return s
r=new A.aP(null,null)
r.w=8
r.x=b
r.y=c
if(c.length>0)r.c=c[0]
r.as=p
q=A.bK(a,r)
a.eC.set(p,q)
return q},
nx(a,b,c){var s,r,q,p,o,n
if(b.w===9){s=b.x
r=b.y.concat(c)}else{r=c
s=b}q=s.as+(";<"+A.eD(r)+">")
p=a.eC.get(q)
if(p!=null)return p
o=new A.aP(null,null)
o.w=9
o.x=s
o.y=r
o.as=q
n=A.bK(a,o)
a.eC.set(q,n)
return n},
pq(a,b,c){var s,r,q="+"+(b+"("+A.eD(c)+")"),p=a.eC.get(q)
if(p!=null)return p
s=new A.aP(null,null)
s.w=10
s.x=b
s.y=c
s.as=q
r=A.bK(a,s)
a.eC.set(q,r)
return r},
pn(a,b,c){var s,r,q,p,o,n=b.as,m=c.a,l=m.length,k=c.b,j=k.length,i=c.c,h=i.length,g="("+A.eD(m)
if(j>0){s=l>0?",":""
g+=s+"["+A.eD(k)+"]"}if(h>0){s=l>0?",":""
g+=s+"{"+A.tN(i)+"}"}r=n+(g+")")
q=a.eC.get(r)
if(q!=null)return q
p=new A.aP(null,null)
p.w=11
p.x=b
p.y=c
p.as=r
o=A.bK(a,p)
a.eC.set(r,o)
return o},
ny(a,b,c,d){var s,r=b.as+("<"+A.eD(c)+">"),q=a.eC.get(r)
if(q!=null)return q
s=A.tP(a,b,c,r,d)
a.eC.set(r,s)
return s},
tP(a,b,c,d,e){var s,r,q,p,o,n,m,l
if(e){s=c.length
r=A.md(s)
for(q=0,p=0;p<s;++p){o=c[p]
if(o.w===1){r[p]=o;++q}}if(q>0){n=A.cu(a,b,r,0)
m=A.dn(a,c,r,0)
return A.ny(a,n,m,c!==m)}}l=new A.aP(null,null)
l.w=12
l.x=b
l.y=c
l.as=d
return A.bK(a,l)},
ph(a,b,c,d){return{u:a,e:b,r:c,s:[],p:0,n:d}},
pj(a){var s,r,q,p,o,n,m,l=a.r,k=a.s
for(s=l.length,r=0;r<s;){q=l.charCodeAt(r)
if(q>=48&&q<=57)r=A.tH(r+1,q,l,k)
else if((((q|32)>>>0)-97&65535)<26||q===95||q===36||q===124)r=A.pi(a,r,l,k,!1)
else if(q===46)r=A.pi(a,r,l,k,!0)
else{++r
switch(q){case 44:break
case 58:k.push(!1)
break
case 33:k.push(!0)
break
case 59:k.push(A.cm(a.u,a.e,k.pop()))
break
case 94:k.push(A.tR(a.u,k.pop()))
break
case 35:k.push(A.eF(a.u,5,"#"))
break
case 64:k.push(A.eF(a.u,2,"@"))
break
case 126:k.push(A.eF(a.u,3,"~"))
break
case 60:k.push(a.p)
a.p=k.length
break
case 62:A.tJ(a,k)
break
case 38:A.tI(a,k)
break
case 63:p=a.u
k.push(A.pp(p,A.cm(p,a.e,k.pop()),a.n))
break
case 47:p=a.u
k.push(A.po(p,A.cm(p,a.e,k.pop()),a.n))
break
case 40:k.push(-3)
k.push(a.p)
a.p=k.length
break
case 41:A.tG(a,k)
break
case 91:k.push(a.p)
a.p=k.length
break
case 93:o=k.splice(a.p)
A.pk(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-1)
break
case 123:k.push(a.p)
a.p=k.length
break
case 125:o=k.splice(a.p)
A.tL(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-2)
break
case 43:n=l.indexOf("(",r)
k.push(l.substring(r,n))
k.push(-4)
k.push(a.p)
a.p=k.length
r=n+1
break
default:throw"Bad character "+q}}}m=k.pop()
return A.cm(a.u,a.e,m)},
tH(a,b,c,d){var s,r,q=b-48
for(s=c.length;a<s;++a){r=c.charCodeAt(a)
if(!(r>=48&&r<=57))break
q=q*10+(r-48)}d.push(q)
return a},
pi(a,b,c,d,e){var s,r,q,p,o,n,m=b+1
for(s=c.length;m<s;++m){r=c.charCodeAt(m)
if(r===46){if(e)break
e=!0}else{if(!((((r|32)>>>0)-97&65535)<26||r===95||r===36||r===124))q=r>=48&&r<=57
else q=!0
if(!q)break}}p=c.substring(b,m)
if(e){s=a.u
o=a.e
if(o.w===9)o=o.x
n=A.tV(s,o.x)[p]
if(n==null)A.C('No "'+p+'" in "'+A.ta(o)+'"')
d.push(A.eG(s,o,n))}else d.push(p)
return m},
tJ(a,b){var s,r=a.u,q=A.pg(a,b),p=b.pop()
if(typeof p=="string")b.push(A.eE(r,p,q))
else{s=A.cm(r,a.e,p)
switch(s.w){case 11:b.push(A.ny(r,s,q,a.n))
break
default:b.push(A.nx(r,s,q))
break}}},
tG(a,b){var s,r,q,p=a.u,o=b.pop(),n=null,m=null
if(typeof o=="number")switch(o){case-1:n=b.pop()
break
case-2:m=b.pop()
break
default:b.push(o)
break}else b.push(o)
s=A.pg(a,b)
o=b.pop()
switch(o){case-3:o=b.pop()
if(n==null)n=p.sEA
if(m==null)m=p.sEA
r=A.cm(p,a.e,o)
q=new A.hk()
q.a=s
q.b=n
q.c=m
b.push(A.pn(p,r,q))
return
case-4:b.push(A.pq(p,b.pop(),s))
return
default:throw A.a(A.eZ("Unexpected state under `()`: "+A.y(o)))}},
tI(a,b){var s=b.pop()
if(0===s){b.push(A.eF(a.u,1,"0&"))
return}if(1===s){b.push(A.eF(a.u,4,"1&"))
return}throw A.a(A.eZ("Unexpected extended operation "+A.y(s)))},
pg(a,b){var s=b.splice(a.p)
A.pk(a.u,a.e,s)
a.p=b.pop()
return s},
cm(a,b,c){if(typeof c=="string")return A.eE(a,c,a.sEA)
else if(typeof c=="number"){b.toString
return A.tK(a,b,c)}else return c},
pk(a,b,c){var s,r=c.length
for(s=0;s<r;++s)c[s]=A.cm(a,b,c[s])},
tL(a,b,c){var s,r=c.length
for(s=2;s<r;s+=3)c[s]=A.cm(a,b,c[s])},
tK(a,b,c){var s,r,q=b.w
if(q===9){if(c===0)return b.x
s=b.y
r=s.length
if(c<=r)return s[c-1]
c-=r
b=b.x
q=b.w}else if(c===0)return b
if(q!==8)throw A.a(A.eZ("Indexed base must be an interface type"))
s=b.y
if(c<=s.length)return s[c-1]
throw A.a(A.eZ("Bad index "+c+" for "+b.i(0)))},
vp(a,b,c){var s,r=b.d
if(r==null)r=b.d=new Map()
s=r.get(c)
if(s==null){s=A.a2(a,b,null,c,null)
r.set(c,s)}return s},
a2(a,b,c,d,e){var s,r,q,p,o,n,m,l,k,j,i
if(b===d)return!0
if(A.cC(d))return!0
s=b.w
if(s===4)return!0
if(A.cC(b))return!1
if(b.w===1)return!0
r=s===13
if(r)if(A.a2(a,c[b.x],c,d,e))return!0
q=d.w
p=t.P
if(b===p||b===t.T){if(q===7)return A.a2(a,b,c,d.x,e)
return d===p||d===t.T||q===6}if(d===t.K){if(s===7)return A.a2(a,b.x,c,d,e)
return s!==6}if(s===7){if(!A.a2(a,b.x,c,d,e))return!1
return A.a2(a,A.nc(a,b),c,d,e)}if(s===6)return A.a2(a,p,c,d,e)&&A.a2(a,b.x,c,d,e)
if(q===7){if(A.a2(a,b,c,d.x,e))return!0
return A.a2(a,b,c,A.nc(a,d),e)}if(q===6)return A.a2(a,b,c,p,e)||A.a2(a,b,c,d.x,e)
if(r)return!1
p=s!==11
if((!p||s===12)&&d===t.b8)return!0
o=s===10
if(o&&d===t.fl)return!0
if(q===12){if(b===t.g)return!0
if(s!==12)return!1
n=b.y
m=d.y
l=n.length
if(l!==m.length)return!1
c=c==null?n:n.concat(c)
e=e==null?m:m.concat(e)
for(k=0;k<l;++k){j=n[k]
i=m[k]
if(!A.a2(a,j,c,i,e)||!A.a2(a,i,e,j,c))return!1}return A.pQ(a,b.x,c,d.x,e)}if(q===11){if(b===t.g)return!0
if(p)return!1
return A.pQ(a,b,c,d,e)}if(s===8){if(q!==8)return!1
return A.uz(a,b,c,d,e)}if(o&&q===10)return A.uE(a,b,c,d,e)
return!1},
pQ(a3,a4,a5,a6,a7){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2
if(!A.a2(a3,a4.x,a5,a6.x,a7))return!1
s=a4.y
r=a6.y
q=s.a
p=r.a
o=q.length
n=p.length
if(o>n)return!1
m=n-o
l=s.b
k=r.b
j=l.length
i=k.length
if(o+j<n+i)return!1
for(h=0;h<o;++h){g=q[h]
if(!A.a2(a3,p[h],a7,g,a5))return!1}for(h=0;h<m;++h){g=l[h]
if(!A.a2(a3,p[o+h],a7,g,a5))return!1}for(h=0;h<i;++h){g=l[m+h]
if(!A.a2(a3,k[h],a7,g,a5))return!1}f=s.c
e=r.c
d=f.length
c=e.length
for(b=0,a=0;a<c;a+=3){a0=e[a]
for(;;){if(b>=d)return!1
a1=f[b]
b+=3
if(a0<a1)return!1
a2=f[b-2]
if(a1<a0){if(a2)return!1
continue}g=e[a+1]
if(a2&&!g)return!1
g=f[b-1]
if(!A.a2(a3,e[a+2],a7,g,a5))return!1
break}}while(b<d){if(f[b+1])return!1
b+=3}return!0},
uz(a,b,c,d,e){var s,r,q,p,o,n=b.x,m=d.x
while(n!==m){s=a.tR[n]
if(s==null)return!1
if(typeof s=="string"){n=s
continue}r=s[m]
if(r==null)return!1
q=r.length
p=q>0?new Array(q):v.typeUniverse.sEA
for(o=0;o<q;++o)p[o]=A.eG(a,b,r[o])
return A.pF(a,p,null,c,d.y,e)}return A.pF(a,b.y,null,c,d.y,e)},
pF(a,b,c,d,e,f){var s,r=b.length
for(s=0;s<r;++s)if(!A.a2(a,b[s],d,e[s],f))return!1
return!0},
uE(a,b,c,d,e){var s,r=b.y,q=d.y,p=r.length
if(p!==q.length)return!1
if(b.x!==d.x)return!1
for(s=0;s<p;++s)if(!A.a2(a,r[s],c,q[s],e))return!1
return!0},
dr(a){var s=a.w,r=!0
if(!(a===t.P||a===t.T))if(!A.cC(a))if(s!==6)r=s===7&&A.dr(a.x)
return r},
cC(a){var s=a.w
return s===2||s===3||s===4||s===5||a===t.X},
pE(a,b){var s,r,q=Object.keys(b),p=q.length
for(s=0;s<p;++s){r=q[s]
a[r]=b[r]}},
md(a){return a>0?new Array(a):v.typeUniverse.sEA},
aP:function aP(a,b){var _=this
_.a=a
_.b=b
_.r=_.f=_.d=_.c=null
_.w=0
_.as=_.Q=_.z=_.y=_.x=null},
hk:function hk(){this.c=this.b=this.a=null},
m7:function m7(a){this.a=a},
hh:function hh(){},
eC:function eC(a){this.a=a},
to(){var s,r,q
if(self.scheduleImmediate!=null)return A.v_()
if(self.MutationObserver!=null&&self.document!=null){s={}
r=self.document.createElement("div")
q=self.document.createElement("span")
s.a=null
new self.MutationObserver(A.cz(new A.kk(s),1)).observe(r,{childList:true})
return new A.kj(s,r,q)}else if(self.setImmediate!=null)return A.v0()
return A.v1()},
tp(a){self.scheduleImmediate(A.cz(new A.kl(a),0))},
tq(a){self.setImmediate(A.cz(new A.km(a),0))},
tr(a){A.ni(B.P,a)},
ni(a,b){var s=B.b.K(a.a,1000)
return A.tM(s<0?0:s,b)},
tM(a,b){var s=new A.m5()
s.fC(a,b)
return s},
j(a){return new A.eb(new A.m($.q,a.h("m<0>")),a.h("eb<0>"))},
i(a,b){a.$2(0,null)
b.b=!0
return b.a},
c(a,b){A.ub(a,b)},
h(a,b){b.O(a)},
f(a,b){b.aO(A.W(a),A.al(a))},
ub(a,b){var s,r,q=new A.mf(b),p=new A.mg(b)
if(a instanceof A.m)a.es(q,p,t.z)
else{s=t.z
if(a instanceof A.m)a.bi(q,p,s)
else{r=new A.m($.q,t.eI)
r.a=8
r.c=a
r.es(q,p,s)}}},
k(a){var s=function(b,c){return function(d,e){while(true){try{b(d,e)
break}catch(r){e=r
d=c}}}}(a,1)
return $.q.cv(new A.mr(s))},
pm(a,b,c){return 0},
du(a){var s
if(t.C.b(a)){s=a.gb_()
if(s!=null)return s}return B.n},
oj(a,b){var s=new A.m($.q,b.h("m<0>"))
A.oT(B.P,new A.iM(a,s))
return s},
dH(a,b){var s,r,q,p,o,n,m,l=null
try{l=a.$0()}catch(q){s=A.W(q)
r=A.al(q)
p=new A.m($.q,b.h("m<0>"))
o=s
n=r
m=A.eO(o,n)
o=new A.T(o,n==null?A.du(o):n)
p.aH(o)
return p}return b.h("K<0>").b(l)?l:A.kP(l,b)},
n0(a,b){var s
b.a(a)
s=new A.m($.q,b.h("m<0>"))
s.br(a)
return s},
rx(a,b){var s
if(!b.b(null))throw A.a(A.aD(null,"computation","The type parameter is not nullable"))
s=new A.m($.q,b.h("m<0>"))
A.oT(a,new A.iL(null,s,b))
return s},
n1(a,b){var s,r,q,p,o,n,m,l,k,j,i={},h=null,g=!1,f=new A.m($.q,b.h("m<u<0>>"))
i.a=null
i.b=0
i.c=i.d=null
s=new A.iO(i,h,g,f)
try{for(n=J.ae(a),m=t.P;n.l();){r=n.gm()
q=i.b
r.bi(new A.iN(i,q,f,b,h,g),s,m);++i.b}n=i.b
if(n===0){n=f
n.bs(A.n([],b.h("t<0>")))
return n}i.a=A.an(n,null,!1,b.h("0?"))}catch(l){p=A.W(l)
o=A.al(l)
if(i.b===0||g){n=f
m=p
k=o
j=A.eO(m,k)
m=new A.T(m,k==null?A.du(m):k)
n.aH(m)
return n}else{i.d=p
i.c=o}}return f},
n_(a,b,c,d){var s=new A.iH(d,null,b,c),r=$.q,q=new A.m(r,c.h("m<0>"))
if(r!==B.e)s=r.cv(s)
a.bq(new A.b3(q,2,null,s,a.$ti.h("@<1>").X(c).h("b3<1,2>")))
return q},
eO(a,b){if($.q===B.e)return null
return null},
pP(a,b){if($.q!==B.e)A.eO(a,b)
if(b==null)if(t.C.b(a)){b=a.gb_()
if(b==null){A.jd(a,B.n)
b=B.n}}else b=B.n
else if(t.C.b(a))A.jd(a,b)
return new A.T(a,b)},
tA(a,b,c){var s=new A.m(b,c.h("m<0>"))
s.a=8
s.c=a
return s},
kP(a,b){var s=new A.m($.q,b.h("m<0>"))
s.a=8
s.c=a
return s},
kT(a,b,c){var s,r,q,p={},o=p.a=a
while(s=o.a,(s&4)!==0){o=o.c
p.a=o}if(o===b){s=A.oR()
b.aH(new A.T(new A.aN(!0,o,null,"Cannot complete a future with itself"),s))
return}r=b.a&1
s=o.a=s|r
if((s&24)===0){q=b.c
b.a=b.a&1|4
b.c=o
o.ei(q)
return}if(!c)if(b.c==null)o=(s&16)===0||r!==0
else o=!1
else o=!0
if(o){q=b.bv()
b.bV(p.a)
A.ck(b,q)
return}b.a^=2
A.dm(null,null,b.b,new A.kU(p,b))},
ck(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g={},f=g.a=a
for(;;){s={}
r=f.a
q=(r&16)===0
p=!q
if(b==null){if(p&&(r&1)===0){f=f.c
A.dl(f.a,f.b)}return}s.a=b
o=b.a
for(f=b;o!=null;f=o,o=n){f.a=null
A.ck(g.a,f)
s.a=o
n=o.a}r=g.a
m=r.c
s.b=p
s.c=m
if(q){l=f.c
l=(l&1)!==0||(l&15)===8}else l=!0
if(l){k=f.b.b
if(p){r=r.b===k
r=!(r||r)}else r=!1
if(r){A.dl(m.a,m.b)
return}j=$.q
if(j!==k)$.q=k
else j=null
f=f.c
if((f&15)===8)new A.kY(s,g,p).$0()
else if(q){if((f&1)!==0)new A.kX(s,m).$0()}else if((f&2)!==0)new A.kW(g,s).$0()
if(j!=null)$.q=j
f=s.c
if(f instanceof A.m){r=s.a.$ti
r=r.h("K<2>").b(f)||!r.y[1].b(f)}else r=!1
if(r){i=s.a.b
if((f.a&24)!==0){h=i.c
i.c=null
b=i.bZ(h)
i.a=f.a&30|i.a&1
i.c=f.c
g.a=f
continue}else A.kT(f,i,!0)
return}}i=s.a.b
h=i.c
i.c=null
b=i.bZ(h)
f=s.b
r=s.c
if(!f){i.a=8
i.c=r}else{i.a=i.a&1|16
i.c=r}g.a=i
f=i}},
uQ(a,b){if(t.V.b(a))return b.cv(a)
if(t.bI.b(a))return a
throw A.a(A.aD(a,"onError",u.c))},
uJ(){var s,r
for(s=$.dk;s!=null;s=$.dk){$.eQ=null
r=s.b
$.dk=r
if(r==null)$.eP=null
s.a.$0()}},
uU(){$.nH=!0
try{A.uJ()}finally{$.eQ=null
$.nH=!1
if($.dk!=null)$.nV().$1(A.q4())}},
q_(a){var s=new A.hb(a),r=$.eP
if(r==null){$.dk=$.eP=s
if(!$.nH)$.nV().$1(A.q4())}else $.eP=r.b=s},
uR(a){var s,r,q,p=$.dk
if(p==null){A.q_(a)
$.eQ=$.eP
return}s=new A.hb(a)
r=$.eQ
if(r==null){s.b=p
$.dk=$.eQ=s}else{q=r.b
s.b=q
$.eQ=r.b=s
if(q==null)$.eP=s}},
vS(a){var s=null,r=$.q
if(B.e===r){A.dm(s,s,B.e,a)
return}A.dm(s,s,r,r.dq(a))},
wf(a){return new A.cp(A.cx(a,"stream",t.K))},
jz(a,b,c,d){var s=null
return c?new A.dh(b,s,s,a,d.h("dh<0>")):new A.bF(b,s,s,a,d.h("bF<0>"))},
nI(a){var s,r,q
if(a==null)return
try{a.$0()}catch(q){s=A.W(q)
r=A.al(q)
A.dl(s,r)}},
nt(a,b){return b==null?A.v2():b},
pb(a,b){if(b==null)b=A.v4()
if(t.da.b(b))return a.cv(b)
if(t.d5.b(b))return b
throw A.a(A.M("handleError callback must take either an Object (the error), or both an Object (the error) and a StackTrace.",null))},
uK(a){},
uM(a,b){A.dl(a,b)},
uL(){},
ui(a,b,c){var s=a.B()
if(s!==$.dt())s.W(new A.mh(b,c))
else b.aJ(c)},
oT(a,b){var s=$.q
if(s===B.e)return A.ni(a,b)
return A.ni(a,s.dq(b))},
dl(a,b){A.uR(new A.mp(a,b))},
pV(a,b,c,d){var s,r=$.q
if(r===c)return d.$0()
$.q=c
s=r
try{r=d.$0()
return r}finally{$.q=s}},
pX(a,b,c,d,e){var s,r=$.q
if(r===c)return d.$1(e)
$.q=c
s=r
try{r=d.$1(e)
return r}finally{$.q=s}},
pW(a,b,c,d,e,f){var s,r=$.q
if(r===c)return d.$2(e,f)
$.q=c
s=r
try{r=d.$2(e,f)
return r}finally{$.q=s}},
dm(a,b,c,d){if(B.e!==c){d=c.dq(d)
d=d}A.q_(d)},
kk:function kk(a){this.a=a},
kj:function kj(a,b,c){this.a=a
this.b=b
this.c=c},
kl:function kl(a){this.a=a},
km:function km(a){this.a=a},
m5:function m5(){},
m6:function m6(a,b){this.a=a
this.b=b},
eb:function eb(a,b){this.a=a
this.b=!1
this.$ti=b},
mf:function mf(a){this.a=a},
mg:function mg(a){this.a=a},
mr:function mr(a){this.a=a},
hF:function hF(a){var _=this
_.a=a
_.e=_.d=_.c=_.b=null},
dg:function dg(a,b){this.a=a
this.$ti=b},
T:function T(a,b){this.a=a
this.b=b},
iM:function iM(a,b){this.a=a
this.b=b},
iL:function iL(a,b,c){this.a=a
this.b=b
this.c=c},
iO:function iO(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
iN:function iN(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
iH:function iH(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
d4:function d4(){},
b2:function b2(a,b){this.a=a
this.$ti=b},
H:function H(a,b){this.a=a
this.$ti=b},
b3:function b3(a,b,c,d,e){var _=this
_.a=null
_.b=a
_.c=b
_.d=c
_.e=d
_.$ti=e},
m:function m(a,b){var _=this
_.a=0
_.b=a
_.c=null
_.$ti=b},
kQ:function kQ(a,b){this.a=a
this.b=b},
kV:function kV(a,b){this.a=a
this.b=b},
kU:function kU(a,b){this.a=a
this.b=b},
kS:function kS(a,b){this.a=a
this.b=b},
kR:function kR(a,b){this.a=a
this.b=b},
kY:function kY(a,b,c){this.a=a
this.b=b
this.c=c},
kZ:function kZ(a,b){this.a=a
this.b=b},
l_:function l_(a){this.a=a},
kX:function kX(a,b){this.a=a
this.b=b},
kW:function kW(a,b){this.a=a
this.b=b},
hb:function hb(a){this.a=a
this.b=null},
a1:function a1(){},
jC:function jC(a,b){this.a=a
this.b=b},
jD:function jD(a,b){this.a=a
this.b=b},
jA:function jA(a){this.a=a},
jB:function jB(a,b,c){this.a=a
this.b=b
this.c=c},
co:function co(){},
m0:function m0(a){this.a=a},
m_:function m_(a){this.a=a},
hG:function hG(){},
hc:function hc(){},
bF:function bF(a,b,c,d,e){var _=this
_.a=null
_.b=0
_.c=null
_.d=a
_.e=b
_.f=c
_.r=d
_.$ti=e},
dh:function dh(a,b,c,d,e){var _=this
_.a=null
_.b=0
_.c=null
_.d=a
_.e=b
_.f=c
_.r=d
_.$ti=e},
as:function as(a,b){this.a=a
this.$ti=b},
d7:function d7(a,b,c,d,e,f,g){var _=this
_.w=a
_.a=b
_.b=c
_.c=d
_.d=e
_.e=f
_.r=_.f=null
_.$ti=g},
eA:function eA(a){this.a=a},
bG:function bG(){},
kr:function kr(a,b,c){this.a=a
this.b=b
this.c=c},
kq:function kq(a){this.a=a},
ez:function ez(){},
hg:function hg(){},
bI:function bI(a){this.b=a
this.a=null},
eg:function eg(a,b){this.b=a
this.c=b
this.a=null},
kJ:function kJ(){},
et:function et(){this.a=0
this.c=this.b=null},
lU:function lU(a,b){this.a=a
this.b=b},
cp:function cp(a){this.a=null
this.b=a
this.c=!1},
bh:function bh(a,b,c){this.a=a
this.b=b
this.$ti=c},
lT:function lT(a,b){this.a=a
this.b=b},
eo:function eo(a,b,c,d,e){var _=this
_.a=null
_.b=0
_.c=null
_.d=a
_.e=b
_.f=c
_.r=d
_.$ti=e},
mh:function mh(a,b){this.a=a
this.b=b},
ei:function ei(){},
da:function da(a,b,c,d,e,f,g){var _=this
_.w=a
_.x=null
_.a=b
_.b=c
_.c=d
_.d=e
_.e=f
_.r=_.f=null
_.$ti=g},
cl:function cl(a,b,c){this.b=a
this.a=b
this.$ti=c},
me:function me(){},
lX:function lX(){},
lY:function lY(a,b){this.a=a
this.b=b},
lZ:function lZ(a,b,c){this.a=a
this.b=b
this.c=c},
mp:function mp(a,b){this.a=a
this.b=b},
pf(a,b){var s=a[b]
return s===a?null:s},
nv(a,b,c){if(c==null)a[b]=a
else a[b]=c},
nu(){var s=Object.create(null)
A.nv(s,"<non-identifier-key>",s)
delete s["<non-identifier-key>"]
return s},
n6(a,b,c){return A.vf(a,new A.bZ(b.h("@<0>").X(c).h("bZ<1,2>")))},
a4(a,b){return new A.bZ(a.h("@<0>").X(b).h("bZ<1,2>"))},
cN(a){return new A.em(a.h("em<0>"))},
nw(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s},
tF(a,b,c){var s=new A.dc(a,b,c.h("dc<0>"))
s.c=a.e
return s},
n7(a){var s,r
if(A.nQ(a))return"{...}"
s=new A.ab("")
try{r={}
$.cv.push(a)
s.a+="{"
r.a=!0
a.Z(0,new A.j3(r,s))
s.a+="}"}finally{$.cv.pop()}r=s.a
return r.charCodeAt(0)==0?r:r},
ov(a){return new A.dP(A.an(A.rF(null),null,!1,a.h("0?")),a.h("dP<0>"))},
rF(a){return 8},
ej:function ej(){},
db:function db(a){var _=this
_.a=0
_.e=_.d=_.c=_.b=null
_.$ti=a},
ek:function ek(a,b){this.a=a
this.$ti=b},
hm:function hm(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
em:function em(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
lS:function lS(a){this.a=a
this.c=this.b=null},
dc:function dc(a,b,c){var _=this
_.a=a
_.b=b
_.d=_.c=null
_.$ti=c},
dO:function dO(a){var _=this
_.b=_.a=0
_.c=null
_.$ti=a},
ht:function ht(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=null
_.d=c
_.e=!1
_.$ti=d},
am:function am(){},
x:function x(){},
N:function N(){},
j2:function j2(a){this.a=a},
j3:function j3(a,b){this.a=a
this.b=b},
dP:function dP(a,b){var _=this
_.a=a
_.d=_.c=_.b=0
_.$ti=b},
hu:function hu(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=null
_.$ti=e},
cX:function cX(){},
ex:function ex(){},
uN(a,b){var s,r,q,p=null
try{p=JSON.parse(a)}catch(r){s=A.W(r)
q=A.a3(String(s),null,null)
throw A.a(q)}q=A.mm(p)
return q},
mm(a){var s
if(a==null)return null
if(typeof a!="object")return a
if(!Array.isArray(a))return new A.hq(a,Object.create(null))
for(s=0;s<a.length;++s)a[s]=A.mm(a[s])
return a},
u4(a,b,c){var s,r,q,p,o=c-b
if(o<=4096)s=$.qI()
else s=new Uint8Array(o)
for(r=J.au(a),q=0;q<o;++q){p=r.j(a,b+q)
if((p&255)!==p)p=255
s[q]=p}return s},
u3(a,b,c,d){var s=a?$.qH():$.qG()
if(s==null)return null
if(0===c&&d===b.length)return A.pD(s,b)
return A.pD(s,b.subarray(c,d))},
pD(a,b){var s,r
try{s=a.decode(b)
return s}catch(r){}return null},
o1(a,b,c,d,e,f){if(B.b.a7(f,4)!==0)throw A.a(A.a3("Invalid base64 padding, padded length must be multiple of four, is "+f,a,c))
if(d+e!==f)throw A.a(A.a3("Invalid base64 padding, '=' not at the end",a,b))
if(e>2)throw A.a(A.a3("Invalid base64 padding, more than two '=' characters",a,b))},
os(a,b,c){return new A.dM(a,b)},
um(a){return a.jl()},
tC(a,b){return new A.lP(a,[],A.v7())},
tE(a,b,c){var s,r=new A.ab("")
A.tD(a,r,b,c)
s=r.a
return s.charCodeAt(0)==0?s:s},
tD(a,b,c,d){var s=A.tC(b,c)
s.cB(a)},
u5(a){switch(a){case 65:return"Missing extension byte"
case 67:return"Unexpected extension byte"
case 69:return"Invalid UTF-8 byte"
case 71:return"Overlong encoding"
case 73:return"Out of unicode range"
case 75:return"Encoded surrogate"
case 77:return"Unfinished UTF-8 octet sequence"
default:return""}},
hq:function hq(a,b){this.a=a
this.b=b
this.c=null},
hr:function hr(a){this.a=a},
mb:function mb(){},
ma:function ma(){},
hZ:function hZ(){},
f2:function f2(){},
f7:function f7(){},
bS:function bS(){},
iB:function iB(){},
dM:function dM(a,b){this.a=a
this.b=b},
ft:function ft(a,b){this.a=a
this.b=b},
j_:function j_(){},
fv:function fv(a){this.b=a},
fu:function fu(a){this.a=a},
lQ:function lQ(){},
lR:function lR(a,b){this.a=a
this.b=b},
lP:function lP(a,b,c){this.c=a
this.a=b
this.b=c},
jY:function jY(){},
h4:function h4(){},
mc:function mc(a){this.b=this.a=0
this.c=a},
eK:function eK(a){this.a=a
this.b=16
this.c=0},
o4(a){var s=A.p9(a,null)
if(s==null)A.C(A.a3("Could not parse BigInt",a,null))
return s},
pa(a,b){var s=A.p9(a,b)
if(s==null)throw A.a(A.a3("Could not parse BigInt",a,null))
return s},
tv(a,b){var s,r,q=$.aM(),p=a.length,o=4-p%4
if(o===4)o=0
for(s=0,r=0;r<p;++r){s=s*10+a.charCodeAt(r)-48;++o
if(o===4){q=q.bn(0,$.nW()).fc(0,A.ec(s))
s=0
o=0}}if(b)return q.ah(0)
return q},
p1(a){if(48<=a&&a<=57)return a-48
return(a|32)-97+10},
tw(a,b,c){var s,r,q,p,o,n,m,l=a.length,k=l-b,j=B.t.i6(k/4),i=new Uint16Array(j),h=j-1,g=k-h*4
for(s=b,r=0,q=0;q<g;++q,s=p){p=s+1
o=A.p1(a.charCodeAt(s))
if(o>=16)return null
r=r*16+o}n=h-1
i[h]=r
for(;s<l;n=m){for(r=0,q=0;q<4;++q,s=p){p=s+1
o=A.p1(a.charCodeAt(s))
if(o>=16)return null
r=r*16+o}m=n-1
i[n]=r}if(j===1&&i[0]===0)return $.aM()
l=A.ar(j,i)
return new A.U(l===0?!1:c,i,l)},
p9(a,b){var s,r,q,p,o
if(a==="")return null
s=$.qD().ij(a)
if(s==null)return null
r=s.b
q=r[1]==="-"
p=r[4]
o=r[3]
if(p!=null)return A.tv(p,q)
if(o!=null)return A.tw(o,2,q)
return null},
ar(a,b){for(;;){if(!(a>0&&b[a-1]===0))break;--a}return a},
nr(a,b,c,d){var s,r=new Uint16Array(d),q=c-b
for(s=0;s<q;++s)r[s]=a[b+s]
return r},
p0(a){var s
if(a===0)return $.aM()
if(a===1)return $.eW()
if(a===2)return $.qE()
if(Math.abs(a)<4294967296)return A.ec(B.b.f3(a))
s=A.ts(a)
return s},
ec(a){var s,r,q,p,o=a<0
if(o){if(a===-9223372036854776e3){s=new Uint16Array(4)
s[3]=32768
r=A.ar(4,s)
return new A.U(r!==0,s,r)}a=-a}if(a<65536){s=new Uint16Array(1)
s[0]=a
r=A.ar(1,s)
return new A.U(r===0?!1:o,s,r)}if(a<=4294967295){s=new Uint16Array(2)
s[0]=a&65535
s[1]=B.b.I(a,16)
r=A.ar(2,s)
return new A.U(r===0?!1:o,s,r)}r=B.b.K(B.b.geE(a)-1,16)+1
s=new Uint16Array(r)
for(q=0;a!==0;q=p){p=q+1
s[q]=a&65535
a=B.b.K(a,65536)}r=A.ar(r,s)
return new A.U(r===0?!1:o,s,r)},
ts(a){var s,r,q,p,o,n,m,l,k
if(isNaN(a)||a==1/0||a==-1/0)throw A.a(A.M("Value must be finite: "+a,null))
s=a<0
if(s)a=-a
a=Math.floor(a)
if(a===0)return $.aM()
r=$.qC()
for(q=r.$flags|0,p=0;p<8;++p){q&2&&A.v(r)
r[p]=0}q=J.qR(B.d.gaa(r))
q.$flags&2&&A.v(q,13)
q.setFloat64(0,a,!0)
q=r[7]
o=r[6]
n=(q<<4>>>0)+(o>>>4)-1075
m=new Uint16Array(4)
m[0]=(r[1]<<8>>>0)+r[0]
m[1]=(r[3]<<8>>>0)+r[2]
m[2]=(r[5]<<8>>>0)+r[4]
m[3]=o&15|16
l=new A.U(!1,m,4)
if(n<0)k=l.aZ(0,-n)
else k=n>0?l.aG(0,n):l
if(s)return k.ah(0)
return k},
ns(a,b,c,d){var s,r,q
if(b===0)return 0
if(c===0&&d===a)return b
for(s=b-1,r=d.$flags|0;s>=0;--s){q=a[s]
r&2&&A.v(d)
d[s+c]=q}for(s=c-1;s>=0;--s){r&2&&A.v(d)
d[s]=0}return b+c},
p7(a,b,c,d){var s,r,q,p,o,n=B.b.K(c,16),m=B.b.a7(c,16),l=16-m,k=B.b.aG(1,l)-1
for(s=b-1,r=d.$flags|0,q=0;s>=0;--s){p=a[s]
o=B.b.aZ(p,l)
r&2&&A.v(d)
d[s+n+1]=(o|q)>>>0
q=B.b.aG((p&k)>>>0,m)}r&2&&A.v(d)
d[n]=q},
p2(a,b,c,d){var s,r,q,p,o=B.b.K(c,16)
if(B.b.a7(c,16)===0)return A.ns(a,b,o,d)
s=b+o+1
A.p7(a,b,c,d)
for(r=d.$flags|0,q=o;--q,q>=0;){r&2&&A.v(d)
d[q]=0}p=s-1
return d[p]===0?p:s},
tx(a,b,c,d){var s,r,q,p,o=B.b.K(c,16),n=B.b.a7(c,16),m=16-n,l=B.b.aG(1,n)-1,k=B.b.aZ(a[o],n),j=b-o-1
for(s=d.$flags|0,r=0;r<j;++r){q=a[r+o+1]
p=B.b.aG((q&l)>>>0,m)
s&2&&A.v(d)
d[r]=(p|k)>>>0
k=B.b.aZ(q,n)}s&2&&A.v(d)
d[j]=k},
kn(a,b,c,d){var s,r=b-d
if(r===0)for(s=b-1;s>=0;--s){r=a[s]-c[s]
if(r!==0)return r}return r},
tt(a,b,c,d,e){var s,r,q
for(s=e.$flags|0,r=0,q=0;q<d;++q){r+=a[q]+c[q]
s&2&&A.v(e)
e[q]=r&65535
r=B.b.I(r,16)}for(q=d;q<b;++q){r+=a[q]
s&2&&A.v(e)
e[q]=r&65535
r=B.b.I(r,16)}s&2&&A.v(e)
e[b]=r},
hd(a,b,c,d,e){var s,r,q
for(s=e.$flags|0,r=0,q=0;q<d;++q){r+=a[q]-c[q]
s&2&&A.v(e)
e[q]=r&65535
r=0-(B.b.I(r,16)&1)}for(q=d;q<b;++q){r+=a[q]
s&2&&A.v(e)
e[q]=r&65535
r=0-(B.b.I(r,16)&1)}},
p8(a,b,c,d,e,f){var s,r,q,p,o,n
if(a===0)return
for(s=d.$flags|0,r=0;--f,f>=0;e=o,c=q){q=c+1
p=a*b[c]+d[e]+r
o=e+1
s&2&&A.v(d)
d[e]=p&65535
r=B.b.K(p,65536)}for(;r!==0;e=o){n=d[e]+r
o=e+1
s&2&&A.v(d)
d[e]=n&65535
r=B.b.K(n,65536)}},
tu(a,b,c){var s,r=b[c]
if(r===a)return 65535
s=B.b.ft((r<<16|b[c-1])>>>0,a)
if(s>65535)return 65535
return s},
vo(a){var s=A.oH(a,null)
if(s!=null)return s
throw A.a(A.a3(a,null,null))},
rp(a,b){a=A.V(a,new Error())
a.stack=b.i(0)
throw a},
an(a,b,c,d){var s,r=c?J.rz(a,d):J.oq(a,d)
if(a!==0&&b!=null)for(s=0;s<r.length;++s)r[s]=b
return r},
rH(a,b,c){var s,r=A.n([],c.h("t<0>"))
for(s=J.ae(a);s.l();)r.push(s.gm())
r.$flags=1
return r},
b9(a,b){var s,r
if(Array.isArray(a))return A.n(a.slice(0),b.h("t<0>"))
s=A.n([],b.h("t<0>"))
for(r=J.ae(a);r.l();)s.push(r.gm())
return s},
j1(a,b){var s=A.rH(a,!1,b)
s.$flags=3
return s},
oS(a,b,c){var s,r,q,p,o
A.ap(b,"start")
s=c==null
r=!s
if(r){q=c-b
if(q<0)throw A.a(A.S(c,b,null,"end",null))
if(q===0)return""}if(Array.isArray(a)){p=a
o=p.length
if(s)c=o
return A.oJ(b>0||c<o?p.slice(b,c):p)}if(t.Z.b(a))return A.tf(a,b,c)
if(r)a=J.r_(a,c)
if(b>0)a=J.hN(a,b)
s=A.b9(a,t.S)
return A.oJ(s)},
tf(a,b,c){var s=a.length
if(b>=s)return""
return A.t1(a,b,c==null||c>s?s:c)},
aO(a,b){return new A.fr(a,A.or(a,!1,b,!1,!1,""))},
ng(a,b,c){var s=J.ae(b)
if(!s.l())return a
if(c.length===0){do a+=A.y(s.gm())
while(s.l())}else{a+=A.y(s.gm())
while(s.l())a=a+c+A.y(s.gm())}return a},
e5(){var s,r,q=A.rX()
if(q==null)throw A.a(A.Y("'Uri.base' is not supported"))
s=$.oY
if(s!=null&&q===$.oX)return s
r=A.jV(q)
$.oY=r
$.oX=q
return r},
oR(){return A.al(new Error())},
og(a,b,c){var s="microsecond"
if(b>999)throw A.a(A.S(b,0,999,s,null))
if(a<-864e13||a>864e13)throw A.a(A.S(a,-864e13,864e13,"millisecondsSinceEpoch",null))
if(a===864e13&&b!==0)throw A.a(A.aD(b,s,"Time including microseconds is outside valid range"))
A.cx(c,"isUtc",t.y)
return a},
ri(a){var s=Math.abs(a),r=a<0?"-":""
if(s>=1000)return""+a
if(s>=100)return r+"0"+s
if(s>=10)return r+"00"+s
return r+"000"+s},
of(a){if(a>=100)return""+a
if(a>=10)return"0"+a
return"00"+a},
fb(a){if(a>=10)return""+a
return"0"+a},
oh(a,b){return new A.dC(a+1000*b)},
oi(a,b){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(q.b===b)return q}throw A.a(A.aD(b,"name","No enum value with that name"))},
rk(a,b){var s,r,q=A.a4(t.N,b)
for(s=0;s<26;++s){r=a[s]
q.p(0,r.b,r)}return q},
dD(a){if(typeof a=="number"||A.dj(a)||a==null)return J.bl(a)
if(typeof a=="string")return JSON.stringify(a)
return A.oI(a)},
rq(a,b){A.cx(a,"error",t.K)
A.cx(b,"stackTrace",t.gm)
A.rp(a,b)},
eZ(a){return new A.eY(a)},
M(a,b){return new A.aN(!1,null,b,a)},
aD(a,b,c){return new A.aN(!0,a,b,c)},
hO(a,b){return a},
na(a){var s=null
return new A.cS(s,s,!1,s,s,a)},
nb(a,b){return new A.cS(null,null,!0,a,b,"Value not in range")},
S(a,b,c,d,e){return new A.cS(b,c,!0,a,d,"Invalid value")},
t3(a,b,c,d){if(a<b||a>c)throw A.a(A.S(a,b,c,d,null))
return a},
t2(a,b,c,d){return A.om(a,d,b,null,c)},
c6(a,b,c){if(0>a||a>c)throw A.a(A.S(a,0,c,"start",null))
if(b!=null){if(a>b||b>c)throw A.a(A.S(b,a,c,"end",null))
return b}return c},
ap(a,b){if(a<0)throw A.a(A.S(a,0,null,b,null))
return a},
ol(a,b){var s=b.b
return new A.dJ(s,!0,a,null,"Index out of range")},
fh(a,b,c,d,e){return new A.dJ(b,!0,a,e,"Index out of range")},
om(a,b,c,d,e){if(0>a||a>=b)throw A.a(A.fh(a,b,c,d,e==null?"index":e))
return a},
Y(a){return new A.e4(a)},
nl(a){return new A.fZ(a)},
L(a){return new A.b0(a)},
a5(a){return new A.f8(a)},
mX(a){return new A.hi(a)},
a3(a,b,c){return new A.aV(a,b,c)},
ry(a,b,c){var s,r
if(A.nQ(a)){if(b==="("&&c===")")return"(...)"
return b+"..."+c}s=A.n([],t.s)
$.cv.push(a)
try{A.uI(a,s)}finally{$.cv.pop()}r=A.ng(b,s,", ")+c
return r.charCodeAt(0)==0?r:r},
iX(a,b,c){var s,r
if(A.nQ(a))return b+"..."+c
s=new A.ab(b)
$.cv.push(a)
try{r=s
r.a=A.ng(r.a,a,", ")}finally{$.cv.pop()}s.a+=c
r=s.a
return r.charCodeAt(0)==0?r:r},
uI(a,b){var s,r,q,p,o,n,m,l=a.gt(a),k=0,j=0
for(;;){if(!(k<80||j<3))break
if(!l.l())return
s=A.y(l.gm())
b.push(s)
k+=s.length+2;++j}if(!l.l()){if(j<=5)return
r=b.pop()
q=b.pop()}else{p=l.gm();++j
if(!l.l()){if(j<=4){b.push(A.y(p))
return}r=A.y(p)
q=b.pop()
k+=r.length+2}else{o=l.gm();++j
for(;l.l();p=o,o=n){n=l.gm();++j
if(j>100){for(;;){if(!(k>75&&j>3))break
k-=b.pop().length+2;--j}b.push("...")
return}}q=A.y(p)
r=A.y(o)
k+=r.length+q.length+4}}if(j>b.length+2){k+=5
m="..."}else m=null
for(;;){if(!(k>80&&b.length>3))break
k-=b.pop().length+2
if(m==null){k+=5
m="..."}}if(m!=null)b.push(m)
b.push(q)
b.push(r)},
n9(a,b,c,d){var s
if(B.k===c){s=J.av(a)
b=J.av(b)
return A.nh(A.bA(A.bA($.mT(),s),b))}if(B.k===d){s=J.av(a)
b=J.av(b)
c=J.av(c)
return A.nh(A.bA(A.bA(A.bA($.mT(),s),b),c))}s=J.av(a)
b=J.av(b)
c=J.av(c)
d=J.av(d)
d=A.nh(A.bA(A.bA(A.bA(A.bA($.mT(),s),b),c),d))
return d},
jV(a5){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3=null,a4=a5.length
if(a4>=5){s=((a5.charCodeAt(4)^58)*3|a5.charCodeAt(0)^100|a5.charCodeAt(1)^97|a5.charCodeAt(2)^116|a5.charCodeAt(3)^97)>>>0
if(s===0)return A.oW(a4<a4?B.a.n(a5,0,a4):a5,5,a3).gf7()
else if(s===32)return A.oW(B.a.n(a5,5,a4),0,a3).gf7()}r=A.an(8,0,!1,t.S)
r[0]=0
r[1]=-1
r[2]=-1
r[7]=-1
r[3]=0
r[4]=0
r[5]=a4
r[6]=a4
if(A.pZ(a5,0,a4,0,r)>=14)r[7]=a4
q=r[1]
if(q>=0)if(A.pZ(a5,0,q,20,r)===20)r[7]=q
p=r[2]+1
o=r[3]
n=r[4]
m=r[5]
l=r[6]
if(l<m)m=l
if(n<p)n=m
else if(n<=q)n=q+1
if(o<p)o=n
k=r[7]<0
j=a3
if(k){k=!1
if(!(p>q+3)){i=o>0
if(!(i&&o+1===n)){if(!B.a.D(a5,"\\",n))if(p>0)h=B.a.D(a5,"\\",p-1)||B.a.D(a5,"\\",p-2)
else h=!1
else h=!0
if(!h){if(!(m<a4&&m===n+2&&B.a.D(a5,"..",n)))h=m>n+2&&B.a.D(a5,"/..",m-3)
else h=!0
if(!h)if(q===4){if(B.a.D(a5,"file",0)){if(p<=0){if(!B.a.D(a5,"/",n)){g="file:///"
s=3}else{g="file://"
s=2}a5=g+B.a.n(a5,n,a4)
m+=s
l+=s
a4=a5.length
p=7
o=7
n=7}else if(n===m){++l
f=m+1
a5=B.a.aT(a5,n,m,"/");++a4
m=f}j="file"}else if(B.a.D(a5,"http",0)){if(i&&o+3===n&&B.a.D(a5,"80",o+1)){l-=3
e=n-3
m-=3
a5=B.a.aT(a5,o,n,"")
a4-=3
n=e}j="http"}}else if(q===5&&B.a.D(a5,"https",0)){if(i&&o+4===n&&B.a.D(a5,"443",o+1)){l-=4
e=n-4
m-=4
a5=B.a.aT(a5,o,n,"")
a4-=3
n=e}j="https"}k=!h}}}}if(k)return new A.aI(a4<a5.length?B.a.n(a5,0,a4):a5,q,p,o,n,m,l,j)
if(j==null)if(q>0)j=A.nA(a5,0,q)
else{if(q===0)A.di(a5,0,"Invalid empty scheme")
j=""}d=a3
if(p>0){c=q+3
b=c<p?A.pz(a5,c,p-1):""
a=A.pw(a5,p,o,!1)
i=o+1
if(i<n){a0=A.oH(B.a.n(a5,i,n),a3)
d=A.m9(a0==null?A.C(A.a3("Invalid port",a5,i)):a0,j)}}else{a=a3
b=""}a1=A.px(a5,n,m,a3,j,a!=null)
a2=m<l?A.py(a5,m+1,l,a3):a3
return A.eI(j,b,a,d,a1,a2,l<a4?A.pv(a5,l+1,a4):a3)},
tm(a){return A.u2(a,0,a.length,B.m,!1)},
h3(a,b,c){throw A.a(A.a3("Illegal IPv4 address, "+a,b,c))},
tj(a,b,c,d,e){var s,r,q,p,o,n,m,l,k="invalid character"
for(s=d.$flags|0,r=b,q=r,p=0,o=0;;){n=q>=c?0:a.charCodeAt(q)
m=n^48
if(m<=9){if(o!==0||q===r){o=o*10+m
if(o<=255){++q
continue}A.h3("each part must be in the range 0..255",a,r)}A.h3("parts must not have leading zeros",a,r)}if(q===r){if(q===c)break
A.h3(k,a,q)}l=p+1
s&2&&A.v(d)
d[e+p]=o
if(n===46){if(l<4){++q
p=l
r=q
o=0
continue}break}if(q===c){if(l===4)return
break}A.h3(k,a,q)
p=l}A.h3("IPv4 address should contain exactly 4 parts",a,q)},
tk(a,b,c){var s
if(b===c)throw A.a(A.a3("Empty IP address",a,b))
if(a.charCodeAt(b)===118){s=A.tl(a,b,c)
if(s!=null)throw A.a(s)
return!1}A.oZ(a,b,c)
return!0},
tl(a,b,c){var s,r,q,p,o="Missing hex-digit in IPvFuture address";++b
for(s=b;;s=r){if(s<c){r=s+1
q=a.charCodeAt(s)
if((q^48)<=9)continue
p=q|32
if(p>=97&&p<=102)continue
if(q===46){if(r-1===b)return new A.aV(o,a,r)
s=r
break}return new A.aV("Unexpected character",a,r-1)}if(s-1===b)return new A.aV(o,a,s)
return new A.aV("Missing '.' in IPvFuture address",a,s)}if(s===c)return new A.aV("Missing address in IPvFuture address, host, cursor",null,null)
for(;;){if((u.v.charCodeAt(a.charCodeAt(s))&16)!==0){++s
if(s<c)continue
return null}return new A.aV("Invalid IPvFuture address character",a,s)}},
oZ(a1,a2,a3){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a="an address must contain at most 8 parts",a0=new A.jW(a1)
if(a3-a2<2)a0.$2("address is too short",null)
s=new Uint8Array(16)
r=-1
q=0
if(a1.charCodeAt(a2)===58)if(a1.charCodeAt(a2+1)===58){p=a2+2
o=p
r=0
q=1}else{a0.$2("invalid start colon",a2)
p=a2
o=p}else{p=a2
o=p}for(n=0,m=!0;;){l=p>=a3?0:a1.charCodeAt(p)
A:{k=l^48
j=!1
if(k<=9)i=k
else{h=l|32
if(h>=97&&h<=102)i=h-87
else break A
m=j}if(p<o+4){n=n*16+i;++p
continue}a0.$2("an IPv6 part can contain a maximum of 4 hex digits",o)}if(p>o){if(l===46){if(m){if(q<=6){A.tj(a1,o,a3,s,q*2)
q+=2
p=a3
break}a0.$2(a,o)}break}g=q*2
s[g]=B.b.I(n,8)
s[g+1]=n&255;++q
if(l===58){if(q<8){++p
o=p
n=0
m=!0
continue}a0.$2(a,p)}break}if(l===58){if(r<0){f=q+1;++p
r=q
q=f
o=p
continue}a0.$2("only one wildcard `::` is allowed",p)}if(r!==q-1)a0.$2("missing part",p)
break}if(p<a3)a0.$2("invalid character",p)
if(q<8){if(r<0)a0.$2("an address without a wildcard must contain exactly 8 parts",a3)
e=r+1
d=q-e
if(d>0){c=e*2
b=16-d*2
B.d.H(s,b,16,s,c)
B.d.dt(s,c,b,0)}}return s},
eI(a,b,c,d,e,f,g){return new A.eH(a,b,c,d,e,f,g)},
ps(a){if(a==="http")return 80
if(a==="https")return 443
return 0},
di(a,b,c){throw A.a(A.a3(c,a,b))},
tX(a,b){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(B.a.a5(q,"/")){s=A.Y("Illegal path character "+q)
throw A.a(s)}}},
m9(a,b){if(a!=null&&a===A.ps(b))return null
return a},
pw(a,b,c,d){var s,r,q,p,o,n,m,l
if(a==null)return null
if(b===c)return""
if(a.charCodeAt(b)===91){s=c-1
if(a.charCodeAt(s)!==93)A.di(a,b,"Missing end `]` to match `[` in host")
r=b+1
q=""
if(a.charCodeAt(r)!==118){p=A.tY(a,r,s)
if(p<s){o=p+1
q=A.pC(a,B.a.D(a,"25",o)?p+3:o,s,"%25")}s=p}n=A.tk(a,r,s)
m=B.a.n(a,r,s)
return"["+(n?m.toLowerCase():m)+q+"]"}for(l=b;l<c;++l)if(a.charCodeAt(l)===58){s=B.a.aP(a,"%",b)
s=s>=b&&s<c?s:c
if(s<c){o=s+1
q=A.pC(a,B.a.D(a,"25",o)?s+3:o,c,"%25")}else q=""
A.oZ(a,b,s)
return"["+B.a.n(a,b,s)+q+"]"}return A.u0(a,b,c)},
tY(a,b,c){var s=B.a.aP(a,"%",b)
return s>=b&&s<c?s:c},
pC(a,b,c,d){var s,r,q,p,o,n,m,l,k,j,i=d!==""?new A.ab(d):null
for(s=b,r=s,q=!0;s<c;){p=a.charCodeAt(s)
if(p===37){o=A.nB(a,s,!0)
n=o==null
if(n&&q){s+=3
continue}if(i==null)i=new A.ab("")
m=i.a+=B.a.n(a,r,s)
if(n)o=B.a.n(a,s,s+3)
else if(o==="%")A.di(a,s,"ZoneID should not contain % anymore")
i.a=m+o
s+=3
r=s
q=!0}else if(p<127&&(u.v.charCodeAt(p)&1)!==0){if(q&&65<=p&&90>=p){if(i==null)i=new A.ab("")
if(r<s){i.a+=B.a.n(a,r,s)
r=s}q=!1}++s}else{l=1
if((p&64512)===55296&&s+1<c){k=a.charCodeAt(s+1)
if((k&64512)===56320){p=65536+((p&1023)<<10)+(k&1023)
l=2}}j=B.a.n(a,r,s)
if(i==null){i=new A.ab("")
n=i}else n=i
n.a+=j
m=A.nz(p)
n.a+=m
s+=l
r=s}}if(i==null)return B.a.n(a,b,c)
if(r<c){j=B.a.n(a,r,c)
i.a+=j}n=i.a
return n.charCodeAt(0)==0?n:n},
u0(a,b,c){var s,r,q,p,o,n,m,l,k,j,i,h=u.v
for(s=b,r=s,q=null,p=!0;s<c;){o=a.charCodeAt(s)
if(o===37){n=A.nB(a,s,!0)
m=n==null
if(m&&p){s+=3
continue}if(q==null)q=new A.ab("")
l=B.a.n(a,r,s)
if(!p)l=l.toLowerCase()
k=q.a+=l
j=3
if(m)n=B.a.n(a,s,s+3)
else if(n==="%"){n="%25"
j=1}q.a=k+n
s+=j
r=s
p=!0}else if(o<127&&(h.charCodeAt(o)&32)!==0){if(p&&65<=o&&90>=o){if(q==null)q=new A.ab("")
if(r<s){q.a+=B.a.n(a,r,s)
r=s}p=!1}++s}else if(o<=93&&(h.charCodeAt(o)&1024)!==0)A.di(a,s,"Invalid character")
else{j=1
if((o&64512)===55296&&s+1<c){i=a.charCodeAt(s+1)
if((i&64512)===56320){o=65536+((o&1023)<<10)+(i&1023)
j=2}}l=B.a.n(a,r,s)
if(!p)l=l.toLowerCase()
if(q==null){q=new A.ab("")
m=q}else m=q
m.a+=l
k=A.nz(o)
m.a+=k
s+=j
r=s}}if(q==null)return B.a.n(a,b,c)
if(r<c){l=B.a.n(a,r,c)
if(!p)l=l.toLowerCase()
q.a+=l}m=q.a
return m.charCodeAt(0)==0?m:m},
nA(a,b,c){var s,r,q
if(b===c)return""
if(!A.pu(a.charCodeAt(b)))A.di(a,b,"Scheme not starting with alphabetic character")
for(s=b,r=!1;s<c;++s){q=a.charCodeAt(s)
if(!(q<128&&(u.v.charCodeAt(q)&8)!==0))A.di(a,s,"Illegal scheme character")
if(65<=q&&q<=90)r=!0}a=B.a.n(a,b,c)
return A.tW(r?a.toLowerCase():a)},
tW(a){if(a==="http")return"http"
if(a==="file")return"file"
if(a==="https")return"https"
if(a==="package")return"package"
return a},
pz(a,b,c){if(a==null)return""
return A.eJ(a,b,c,16,!1,!1)},
px(a,b,c,d,e,f){var s,r=e==="file",q=r||f
if(a==null)return r?"/":""
else s=A.eJ(a,b,c,128,!0,!0)
if(s.length===0){if(r)return"/"}else if(q&&!B.a.A(s,"/"))s="/"+s
return A.u_(s,e,f)},
u_(a,b,c){var s=b.length===0
if(s&&!c&&!B.a.A(a,"/")&&!B.a.A(a,"\\"))return A.nC(a,!s||c)
return A.cr(a)},
py(a,b,c,d){if(a!=null)return A.eJ(a,b,c,256,!0,!1)
return null},
pv(a,b,c){if(a==null)return null
return A.eJ(a,b,c,256,!0,!1)},
nB(a,b,c){var s,r,q,p,o,n=b+2
if(n>=a.length)return"%"
s=a.charCodeAt(b+1)
r=a.charCodeAt(n)
q=A.mA(s)
p=A.mA(r)
if(q<0||p<0)return"%"
o=q*16+p
if(o<127&&(u.v.charCodeAt(o)&1)!==0)return A.aX(c&&65<=o&&90>=o?(o|32)>>>0:o)
if(s>=97||r>=97)return B.a.n(a,b,b+3).toUpperCase()
return null},
nz(a){var s,r,q,p,o,n="0123456789ABCDEF"
if(a<=127){s=new Uint8Array(3)
s[0]=37
s[1]=n.charCodeAt(a>>>4)
s[2]=n.charCodeAt(a&15)}else{if(a>2047)if(a>65535){r=240
q=4}else{r=224
q=3}else{r=192
q=2}s=new Uint8Array(3*q)
for(p=0;--q,q>=0;r=128){o=B.b.hI(a,6*q)&63|r
s[p]=37
s[p+1]=n.charCodeAt(o>>>4)
s[p+2]=n.charCodeAt(o&15)
p+=3}}return A.oS(s,0,null)},
eJ(a,b,c,d,e,f){var s=A.pB(a,b,c,d,e,f)
return s==null?B.a.n(a,b,c):s},
pB(a,b,c,d,e,f){var s,r,q,p,o,n,m,l,k,j=null,i=u.v
for(s=!e,r=b,q=r,p=j;r<c;){o=a.charCodeAt(r)
if(o<127&&(i.charCodeAt(o)&d)!==0)++r
else{n=1
if(o===37){m=A.nB(a,r,!1)
if(m==null){r+=3
continue}if("%"===m)m="%25"
else n=3}else if(o===92&&f)m="/"
else if(s&&o<=93&&(i.charCodeAt(o)&1024)!==0){A.di(a,r,"Invalid character")
n=j
m=n}else{if((o&64512)===55296){l=r+1
if(l<c){k=a.charCodeAt(l)
if((k&64512)===56320){o=65536+((o&1023)<<10)+(k&1023)
n=2}}}m=A.nz(o)}if(p==null){p=new A.ab("")
l=p}else l=p
l.a=(l.a+=B.a.n(a,q,r))+m
r+=n
q=r}}if(p==null)return j
if(q<c){s=B.a.n(a,q,c)
p.a+=s}s=p.a
return s.charCodeAt(0)==0?s:s},
pA(a){if(B.a.A(a,"."))return!0
return B.a.iB(a,"/.")!==-1},
cr(a){var s,r,q,p,o,n
if(!A.pA(a))return a
s=A.n([],t.s)
for(r=a.split("/"),q=r.length,p=!1,o=0;o<q;++o){n=r[o]
if(n===".."){if(s.length!==0){s.pop()
if(s.length===0)s.push("")}p=!0}else{p="."===n
if(!p)s.push(n)}}if(p)s.push("")
return B.c.bd(s,"/")},
nC(a,b){var s,r,q,p,o,n
if(!A.pA(a))return!b?A.pt(a):a
s=A.n([],t.s)
for(r=a.split("/"),q=r.length,p=!1,o=0;o<q;++o){n=r[o]
if(".."===n){if(s.length!==0&&B.c.gap(s)!=="..")s.pop()
else s.push("..")
p=!0}else{p="."===n
if(!p)s.push(n.length===0&&s.length===0?"./":n)}}if(s.length===0)return"./"
if(p)s.push("")
if(!b)s[0]=A.pt(s[0])
return B.c.bd(s,"/")},
pt(a){var s,r,q=a.length
if(q>=2&&A.pu(a.charCodeAt(0)))for(s=1;s<q;++s){r=a.charCodeAt(s)
if(r===58)return B.a.n(a,0,s)+"%3A"+B.a.T(a,s+1)
if(r>127||(u.v.charCodeAt(r)&8)===0)break}return a},
u1(a,b){if(a.iG("package")&&a.c==null)return A.q0(b,0,b.length)
return-1},
tZ(a,b){var s,r,q
for(s=0,r=0;r<2;++r){q=a.charCodeAt(b+r)
if(48<=q&&q<=57)s=s*16+q-48
else{q|=32
if(97<=q&&q<=102)s=s*16+q-87
else throw A.a(A.M("Invalid URL encoding",null))}}return s},
u2(a,b,c,d,e){var s,r,q,p,o=b
for(;;){if(!(o<c)){s=!0
break}r=a.charCodeAt(o)
if(r<=127)q=r===37
else q=!0
if(q){s=!1
break}++o}if(s)if(B.m===d)return B.a.n(a,b,c)
else p=new A.f6(B.a.n(a,b,c))
else{p=A.n([],t.t)
for(q=a.length,o=b;o<c;++o){r=a.charCodeAt(o)
if(r>127)throw A.a(A.M("Illegal percent encoding in URI",null))
if(r===37){if(o+3>q)throw A.a(A.M("Truncated URI",null))
p.push(A.tZ(a,o+1))
o+=2}else p.push(r)}}return d.cb(p)},
pu(a){var s=a|32
return 97<=s&&s<=122},
oW(a,b,c){var s,r,q,p,o,n,m,l,k="Invalid MIME type",j=A.n([b-1],t.t)
for(s=a.length,r=b,q=-1,p=null;r<s;++r){p=a.charCodeAt(r)
if(p===44||p===59)break
if(p===47){if(q<0){q=r
continue}throw A.a(A.a3(k,a,r))}}if(q<0&&r>b)throw A.a(A.a3(k,a,r))
while(p!==44){j.push(r);++r
for(o=-1;r<s;++r){p=a.charCodeAt(r)
if(p===61){if(o<0)o=r}else if(p===59||p===44)break}if(o>=0)j.push(o)
else{n=B.c.gap(j)
if(p!==44||r!==n+7||!B.a.D(a,"base64",n+1))throw A.a(A.a3("Expecting '='",a,r))
break}}j.push(r)
m=r+1
if((j.length&1)===1)a=B.aF.iP(a,m,s)
else{l=A.pB(a,m,s,256,!0,!1)
if(l!=null)a=B.a.aT(a,m,s,l)}return new A.jU(a,j,c)},
pZ(a,b,c,d,e){var s,r,q
for(s=b;s<c;++s){r=a.charCodeAt(s)^96
if(r>95)r=31
q='\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xe1\xe1\xe1\x01\xe1\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xe1\xe3\xe1\xe1\x01\xe1\x01\xe1\xcd\x01\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x0e\x03\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01"\x01\xe1\x01\xe1\xac\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xe1\xe1\xe1\x01\xe1\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xe1\xea\xe1\xe1\x01\xe1\x01\xe1\xcd\x01\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\n\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01"\x01\xe1\x01\xe1\xac\xeb\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\xeb\xeb\xeb\x8b\xeb\xeb\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\xeb\x83\xeb\xeb\x8b\xeb\x8b\xeb\xcd\x8b\xeb\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x92\x83\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\x8b\xeb\x8b\xeb\x8b\xeb\xac\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xeb\xeb\v\xeb\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xebD\xeb\xeb\v\xeb\v\xeb\xcd\v\xeb\v\v\v\v\v\v\v\v\x12D\v\v\v\v\v\v\v\v\v\v\xeb\v\xeb\v\xeb\xac\xe5\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\xe5\xe5\xe5\x05\xe5D\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe8\x8a\xe5\xe5\x05\xe5\x05\xe5\xcd\x05\xe5\x05\x05\x05\x05\x05\x05\x05\x05\x05\x8a\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05f\x05\xe5\x05\xe5\xac\xe5\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05\xe5\xe5\xe5\x05\xe5D\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\xe5\x8a\xe5\xe5\x05\xe5\x05\xe5\xcd\x05\xe5\x05\x05\x05\x05\x05\x05\x05\x05\x05\x8a\x05\x05\x05\x05\x05\x05\x05\x05\x05\x05f\x05\xe5\x05\xe5\xac\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7D\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\x8a\xe7\xe7\xe7\xe7\xe7\xe7\xcd\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\x8a\xe7\x07\x07\x07\x07\x07\x07\x07\x07\x07\xe7\xe7\xe7\xe7\xe7\xac\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7D\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\x8a\xe7\xe7\xe7\xe7\xe7\xe7\xcd\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\xe7\x8a\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\xe7\xe7\xe7\xe7\xe7\xac\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\x05\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xeb\xeb\v\xeb\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xea\xeb\xeb\v\xeb\v\xeb\xcd\v\xeb\v\v\v\v\v\v\v\v\x10\xea\v\v\v\v\v\v\v\v\v\v\xeb\v\xeb\v\xeb\xac\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xeb\xeb\v\xeb\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xea\xeb\xeb\v\xeb\v\xeb\xcd\v\xeb\v\v\v\v\v\v\v\v\x12\n\v\v\v\v\v\v\v\v\v\v\xeb\v\xeb\v\xeb\xac\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xeb\xeb\v\xeb\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xea\xeb\xeb\v\xeb\v\xeb\xcd\v\xeb\v\v\v\v\v\v\v\v\v\n\v\v\v\v\v\v\v\v\v\v\xeb\v\xeb\v\xeb\xac\xec\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\xec\xec\xec\f\xec\xec\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\f\xec\xec\xec\xec\f\xec\f\xec\xcd\f\xec\f\f\f\f\f\f\f\f\f\xec\f\f\f\f\f\f\f\f\f\f\xec\f\xec\f\xec\f\xed\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\xed\xed\xed\r\xed\xed\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\xed\xed\xed\xed\r\xed\r\xed\xed\r\xed\r\r\r\r\r\r\r\r\r\xed\r\r\r\r\r\r\r\r\r\r\xed\r\xed\r\xed\r\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xe1\xe1\xe1\x01\xe1\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xe1\xea\xe1\xe1\x01\xe1\x01\xe1\xcd\x01\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x0f\xea\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01"\x01\xe1\x01\xe1\xac\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xe1\xe1\xe1\x01\xe1\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\xe1\xe9\xe1\xe1\x01\xe1\x01\xe1\xcd\x01\xe1\x01\x01\x01\x01\x01\x01\x01\x01\x01\t\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01"\x01\xe1\x01\xe1\xac\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xeb\xeb\v\xeb\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xea\xeb\xeb\v\xeb\v\xeb\xcd\v\xeb\v\v\v\v\v\v\v\v\x11\xea\v\v\v\v\v\v\v\v\v\v\xeb\v\xeb\v\xeb\xac\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xeb\xeb\v\xeb\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xe9\xeb\xeb\v\xeb\v\xeb\xcd\v\xeb\v\v\v\v\v\v\v\v\v\t\v\v\v\v\v\v\v\v\v\v\xeb\v\xeb\v\xeb\xac\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xeb\xeb\v\xeb\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xea\xeb\xeb\v\xeb\v\xeb\xcd\v\xeb\v\v\v\v\v\v\v\v\x13\xea\v\v\v\v\v\v\v\v\v\v\xeb\v\xeb\v\xeb\xac\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xeb\xeb\v\xeb\xeb\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\v\xeb\xea\xeb\xeb\v\xeb\v\xeb\xcd\v\xeb\v\v\v\v\v\v\v\v\v\xea\v\v\v\v\v\v\v\v\v\v\xeb\v\xeb\v\xeb\xac\xf5\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\xf5\x15\xf5\x15\x15\xf5\x15\x15\x15\x15\x15\x15\x15\x15\x15\x15\xf5\xf5\xf5\xf5\xf5\xf5'.charCodeAt(d*96+r)
d=q&31
e[q>>>5]=s}return d},
pl(a){if(a.b===7&&B.a.A(a.a,"package")&&a.c<=0)return A.q0(a.a,a.e,a.f)
return-1},
q0(a,b,c){var s,r,q
for(s=b,r=0;s<c;++s){q=a.charCodeAt(s)
if(q===47)return r!==0?s:-1
if(q===37||q===58)return-1
r|=q^46}return-1},
uj(a,b,c){var s,r,q,p,o,n
for(s=a.length,r=0,q=0;q<s;++q){p=b.charCodeAt(c+q)
o=a.charCodeAt(q)^p
if(o!==0){if(o===32){n=p|o
if(97<=n&&n<=122){r=32
continue}}return-1}}return r},
U:function U(a,b,c){this.a=a
this.b=b
this.c=c},
ko:function ko(){},
kp:function kp(){},
hj:function hj(a,b){this.a=a
this.$ti=b},
dB:function dB(a,b,c){this.a=a
this.b=b
this.c=c},
dC:function dC(a){this.a=a},
kK:function kK(){},
G:function G(){},
eY:function eY(a){this.a=a},
bd:function bd(){},
aN:function aN(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
cS:function cS(a,b,c,d,e,f){var _=this
_.e=a
_.f=b
_.a=c
_.b=d
_.c=e
_.d=f},
dJ:function dJ(a,b,c,d,e){var _=this
_.f=a
_.a=b
_.b=c
_.c=d
_.d=e},
e4:function e4(a){this.a=a},
fZ:function fZ(a){this.a=a},
b0:function b0(a){this.a=a},
f8:function f8(a){this.a=a},
fJ:function fJ(){},
e0:function e0(){},
hi:function hi(a){this.a=a},
aV:function aV(a,b,c){this.a=a
this.b=b
this.c=c},
fk:function fk(){},
d:function d(){},
ao:function ao(a,b,c){this.a=a
this.b=b
this.$ti=c},
B:function B(){},
l:function l(){},
hE:function hE(){},
ab:function ab(a){this.a=a},
jW:function jW(a){this.a=a},
eH:function eH(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.y=_.x=_.w=$},
jU:function jU(a,b,c){this.a=a
this.b=b
this.c=c},
aI:function aI(a,b,c,d,e,f,g,h){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=h
_.x=null},
hf:function hf(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.y=_.x=_.w=$},
fe:function fe(a){this.a=a},
rG(a){return a},
rC(a){return a},
oo(a,b){var s,r,q,p,o
if(b.length===0)return!1
s=b.split(".")
r=v.G
for(q=s.length,p=0;p<q;++p,r=o){o=r[s[p]]
A.pG(o)
if(o==null)return!1}return a instanceof t.g.a(r)},
rw(a){return new v.G.Promise(A.b4(new A.iK(a)))},
fH:function fH(a){this.a=a},
iK:function iK(a){this.a=a},
iI:function iI(a){this.a=a},
iJ:function iJ(a){this.a=a},
aK(a){var s
if(typeof a=="function")throw A.a(A.M("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d){return b(c,d,arguments.length)}}(A.ud,a)
s[$.cD()]=a
return s},
b4(a){var s
if(typeof a=="function")throw A.a(A.M("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d,e){return b(c,d,e,arguments.length)}}(A.ue,a)
s[$.cD()]=a
return s},
eN(a){var s
if(typeof a=="function")throw A.a(A.M("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d,e,f){return b(c,d,e,f,arguments.length)}}(A.uf,a)
s[$.cD()]=a
return s},
mo(a){var s
if(typeof a=="function")throw A.a(A.M("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d,e,f,g){return b(c,d,e,f,g,arguments.length)}}(A.ug,a)
s[$.cD()]=a
return s},
nF(a){var s
if(typeof a=="function")throw A.a(A.M("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d,e,f,g,h){return b(c,d,e,f,g,h,arguments.length)}}(A.uh,a)
s[$.cD()]=a
return s},
uc(a){return a.$0()},
ud(a,b,c){if(c>=1)return a.$1(b)
return a.$0()},
ue(a,b,c,d){if(d>=2)return a.$2(b,c)
if(d===1)return a.$1(b)
return a.$0()},
uf(a,b,c,d,e){if(e>=3)return a.$3(b,c,d)
if(e===2)return a.$2(b,c)
if(e===1)return a.$1(b)
return a.$0()},
ug(a,b,c,d,e,f){if(f>=4)return a.$4(b,c,d,e)
if(f===3)return a.$3(b,c,d)
if(f===2)return a.$2(b,c)
if(f===1)return a.$1(b)
return a.$0()},
uh(a,b,c,d,e,f,g){if(g>=5)return a.$5(b,c,d,e,f)
if(g===4)return a.$4(b,c,d,e)
if(g===3)return a.$3(b,c,d)
if(g===2)return a.$2(b,c)
if(g===1)return a.$1(b)
return a.$0()},
pU(a){return a==null||A.dj(a)||typeof a=="number"||typeof a=="string"||t.gj.b(a)||t.p.b(a)||t.go.b(a)||t.dQ.b(a)||t.h7.b(a)||t.an.b(a)||t.bv.b(a)||t.h4.b(a)||t.gN.b(a)||t.J.b(a)||t.fd.b(a)},
qa(a){if(A.pU(a))return a
return new A.mF(new A.db(t.hg)).$1(a)},
nO(a,b){return a[b]},
hI(a,b,c){return a[b].apply(a,c)},
cw(a,b){var s,r
if(b==null)return new a()
if(b instanceof Array)switch(b.length){case 0:return new a()
case 1:return new a(b[0])
case 2:return new a(b[0],b[1])
case 3:return new a(b[0],b[1],b[2])
case 4:return new a(b[0],b[1],b[2],b[3])}s=[null]
B.c.am(s,b)
r=a.bind.apply(a,s)
String(r)
return new r()},
Q(a,b){var s=new A.m($.q,b.h("m<0>")),r=new A.b2(s,b.h("b2<0>"))
a.then(A.cz(new A.mJ(r),1),A.cz(new A.mK(r),1))
return s},
pT(a){return a==null||typeof a==="boolean"||typeof a==="number"||typeof a==="string"||a instanceof Int8Array||a instanceof Uint8Array||a instanceof Uint8ClampedArray||a instanceof Int16Array||a instanceof Uint16Array||a instanceof Int32Array||a instanceof Uint32Array||a instanceof Float32Array||a instanceof Float64Array||a instanceof ArrayBuffer||a instanceof DataView},
q6(a){if(A.pT(a))return a
return new A.mw(new A.db(t.hg)).$1(a)},
mF:function mF(a){this.a=a},
mJ:function mJ(a){this.a=a},
mK:function mK(a){this.a=a},
mw:function mw(a){this.a=a},
oK(){return $.qn()},
lM:function lM(){},
lN:function lN(a){this.a=a},
fG:function fG(){},
h1:function h1(){},
jl:function jl(a){this.a=a
this.b=0},
od(a,b){if(a==null)a="."
return new A.f9(b,a)},
q1(a,b){var s,r,q,p,o,n,m,l
for(s=b.length,r=1;r<s;++r){if(b[r]==null||b[r-1]!=null)continue
for(;s>=1;s=q){q=s-1
if(b[q]!=null)break}p=new A.ab("")
o=a+"("
p.a=o
n=A.ac(b)
m=n.h("cc<1>")
l=new A.cc(b,0,s,m)
l.fw(b,0,s,n.c)
m=o+new A.aa(l,new A.mq(),m.h("aa<a7.E,o>")).bd(0,", ")
p.a=m
p.a=m+("): part "+(r-1)+" was null, but part "+r+" was not.")
throw A.a(A.M(p.i(0),null))}},
f9:function f9(a,b){this.a=a
this.b=b},
ic:function ic(){},
id:function id(){},
mq:function mq(){},
de:function de(a){this.a=a},
df:function df(a){this.a=a},
iW:function iW(){},
fK(a,b){var s,r,q,p,o,n=b.fg(a)
b.a6(a)
if(n!=null)a=B.a.T(a,n.length)
s=t.s
r=A.n([],s)
q=A.n([],s)
s=a.length
if(s!==0&&b.C(a.charCodeAt(0))){q.push(a[0])
p=1}else{q.push("")
p=0}for(o=p;o<s;++o)if(b.C(a.charCodeAt(o))){r.push(B.a.n(a,p,o))
q.push(a[o])
p=o+1}if(p<s){r.push(B.a.T(a,p))
q.push("")}return new A.ja(b,n,r,q)},
ja:function ja(a,b,c,d){var _=this
_.a=a
_.b=b
_.d=c
_.e=d},
oy(a){return new A.dV(a)},
dV:function dV(a){this.a=a},
tg(){var s,r,q,p,o,n,m,l,k=null
if(A.e5().gaX()!=="file")return $.eV()
if(!B.a.eK(A.e5().gag(),"/"))return $.eV()
s=A.pz(k,0,0)
r=A.pw(k,0,0,!1)
q=A.py(k,0,0,k)
p=A.pv(k,0,0)
o=A.m9(k,"")
if(r==null)if(s.length===0)n=o!=null
else n=!0
else n=!1
if(n)r=""
n=r==null
m=!n
l=A.px("a/b",0,3,k,"",m)
if(n&&!B.a.A(l,"/"))l=A.nC(l,m)
else l=A.cr(l)
if(A.eI("",s,n&&B.a.A(l,"//")?"":r,o,l,q,p).dP()==="a\\b")return $.hK()
return $.qo()},
jE:function jE(){},
jb:function jb(a,b,c){this.d=a
this.e=b
this.f=c},
jX:function jX(a,b,c,d){var _=this
_.d=a
_.e=b
_.f=c
_.r=d},
kc:function kc(a,b,c,d){var _=this
_.d=a
_.e=b
_.f=c
_.r=d},
vT(a){a.eG(B.aE,!0,!1,new A.mL(),"powersync_diff")},
mL:function mL(){},
vU(a){var s
A.vT(a)
s=new A.jZ()
a.c8(B.p,new A.mM(s),"uuid")
a.c8(B.p,new A.mN(s),"gen_random_uuid")
a.c8(B.aD,new A.mO(),"powersync_sleep")
a.c8(B.p,new A.mP(),"powersync_connection_name")},
jc:function jc(){},
mM:function mM(a){this.a=a},
mN:function mN(a){this.a=a},
mO:function mO(){},
mP:function mP(){},
td(a){var s
A:{if(18===a){s=B.ac
break A}if(23===a){s=B.ad
break A}if(9===a){s=B.ae
break A}s=null
break A}return s},
cZ:function cZ(a,b){this.a=a
this.b=b},
aG:function aG(a,b,c){this.a=a
this.b=b
this.c=c},
oQ(a,b,c,d,e,f,g){return new A.ca(b,c,a,g,f,d,e)},
ca:function ca(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g},
jx:function jx(){},
cF:function cF(a){this.a=a},
jg:function jg(){},
fW:function fW(a,b){this.a=a
this.b=b},
jh:function jh(){},
jj:function jj(){},
ji:function ji(){},
cT:function cT(){},
cU:function cU(){},
uo(a,b,c){var s,r,q,p,o,n=new A.h5(c,A.an(c.b,null,!1,t.X))
try{A.pN(a,b.$1(n))}catch(r){s=A.W(r)
q=B.h.ac(A.dD(s))
p=a.b
o=p.b8(q)
p=p.d
p.sqlite3_result_error(a.c,o,q.length)
p.dart_sqlite3_free(o)}finally{}},
pN(a,b){var s,r,q,p,o
A:{s=null
if(b==null){a.b.d.sqlite3_result_null(a.c)
break A}if(A.ct(b)){a.b.d.sqlite3_result_int64(a.c,v.G.BigInt(A.p0(b).i(0)))
break A}if(b instanceof A.U){a.b.d.sqlite3_result_int64(a.c,v.G.BigInt(A.o3(b).i(0)))
break A}if(typeof b=="number"){a.b.d.sqlite3_result_double(a.c,b)
break A}if(A.dj(b)){a.b.d.sqlite3_result_int64(a.c,v.G.BigInt(A.p0(b?1:0).i(0)))
break A}if(typeof b=="string"){r=B.h.ac(b)
q=a.b
p=q.b8(r)
q=q.d
q.sqlite3_result_text(a.c,p,r.length,-1)
q.dart_sqlite3_free(p)
break A}if(t.L.b(b)){q=a.b
p=q.b8(b)
q=q.d
q.sqlite3_result_blob64(a.c,p,v.G.BigInt(J.aw(b)),-1)
q.dart_sqlite3_free(p)
break A}if(t.cV.b(b)){A.pN(a,b.a)
o=b.b
q=a.b.d.sqlite3_result_subtype
if(q!=null)q.call(null,a.c,o)
break A}s=A.C(A.aD(b,"result","Unsupported type"))}return s},
ff:function ff(a,b,c,d){var _=this
_.b=a
_.c=b
_.d=c
_.e=d},
ij:function ij(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.f=_.e=_.d=null
_.r=!1},
it:function it(a){this.a=a},
is:function is(a){this.a=a},
iu:function iu(a){this.a=a},
iq:function iq(a){this.a=a},
ip:function ip(a){this.a=a},
ir:function ir(a){this.a=a},
il:function il(a){this.a=a},
ik:function ik(a){this.a=a},
im:function im(a){this.a=a},
iv:function iv(a){this.a=a},
io:function io(a,b){this.a=a
this.b=b},
h5:function h5(a,b){this.a=a
this.b=b},
bJ:function bJ(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=null
_.d=c
_.e=d
_.r=_.f=null
_.$ti=e},
m1:function m1(a,b){this.a=a
this.b=b},
m2:function m2(a,b,c){this.a=a
this.b=b
this.c=c},
m3:function m3(a,b,c){this.a=a
this.b=b
this.c=c},
b7:function b7(){},
my:function my(){},
jw:function jw(){},
cJ:function cJ(a){this.b=a
this.c=!0
this.d=!1},
e1:function e1(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=null},
n3(a,b){var s=$.eU()
return new A.fg(A.a4(t.N,t.fN),s,a)},
fg:function fg(a,b,c){this.d=a
this.b=b
this.a=c},
hn:function hn(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=0},
oM(a,b,c){var s=new A.fQ(c,a,b,B.bb)
s.fI()
return s},
ig:function ig(){},
fQ:function fQ(a,b,c,d){var _=this
_.d=a
_.a=b
_.b=c
_.c=d},
aY:function aY(a,b){this.a=a
this.b=b},
lW:function lW(a){this.a=a
this.b=-1},
hy:function hy(){},
hz:function hz(){},
hA:function hA(){},
hB:function hB(){},
j9:function j9(a,b){this.a=a
this.b=b},
i1:function i1(){},
fj:function fj(a){this.a=a},
bC(a){return new A.aq(a)},
o2(a,b){var s,r,q,p
if(b==null)b=$.eU()
for(s=a.length,r=a.$flags|0,q=0;q<s;++q){p=b.bK(256)
r&2&&A.v(a)
a[q]=p}},
aq:function aq(a){this.a=a},
dZ:function dZ(a){this.a=a},
bf:function bf(){},
f4:function f4(){},
f3:function f3(){},
k6:function k6(a){this.b=a},
k0:function k0(a,b){this.a=a
this.b=b},
k8:function k8(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
k7:function k7(a,b,c){this.b=a
this.c=b
this.d=c},
bD:function bD(a,b){this.b=a
this.c=b},
bg:function bg(a,b){this.a=a
this.b=b},
d3:function d3(a,b,c){this.a=a
this.b=b
this.c=c},
dv:function dv(a,b){this.a=a
this.$ti=b},
hP:function hP(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
hR:function hR(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
hQ:function hQ(a,b,c){this.a=a
this.b=b
this.c=c},
aT(a,b){var s=new A.m($.q,b.h("m<0>")),r=new A.H(s,b.h("H<0>")),q=t.m
A.ag(a,"success",new A.i4(r,a,b),!1,q)
A.ag(a,"error",new A.i5(r,a),!1,q)
return s},
rf(a,b){var s=new A.m($.q,b.h("m<0>")),r=new A.H(s,b.h("H<0>")),q=t.m
A.ag(a,"success",new A.i9(r,a,b),!1,q)
A.ag(a,"error",new A.ia(r,a),!1,q)
A.ag(a,"blocked",new A.ib(r,a),!1,q)
return s},
ch:function ch(a,b){var _=this
_.c=_.b=_.a=null
_.d=a
_.$ti=b},
kH:function kH(a,b){this.a=a
this.b=b},
kI:function kI(a,b){this.a=a
this.b=b},
i4:function i4(a,b,c){this.a=a
this.b=b
this.c=c},
i5:function i5(a,b){this.a=a
this.b=b},
i9:function i9(a,b,c){this.a=a
this.b=b
this.c=c},
ia:function ia(a,b){this.a=a
this.b=b},
ib:function ib(a,b){this.a=a
this.b=b},
hJ(){var s=v.G.navigator
if("storage" in s)return s.storage
return null},
iE(a,b,c){var s=a.read(b,c)
return s},
mZ(a,b,c){var s=a.write(b,c)
return s},
mY(a,b){return A.Q(a.removeEntry(b,{recursive:!1}),t.X)},
rs(a){var s=t.cO
if(!(v.G.Symbol.asyncIterator in a))A.C(A.M("Target object does not implement the async iterable interface",null))
return new A.cl(new A.iD(),new A.dv(a,s),s.h("cl<a1.T,e>"))},
iD:function iD(){},
k1(a,b){var s=0,r=A.j(t.m),q,p,o,n
var $async$k1=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:n={}
b.Z(0,new A.k3(n))
s=3
return A.c(A.Q(v.G.WebAssembly.instantiateStreaming(a,n),t.m),$async$k1)
case 3:p=d
o=p.instance.exports
if("_initialize" in o)t.g.a(o._initialize).call()
q=p.instance
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$k1,r)},
k3:function k3(a){this.a=a},
k2:function k2(a){this.a=a},
k5(a,b){var s=0,r=A.j(t.n),q,p,o,n
var $async$k5=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:p=v.G
o=a.geO()?new p.URL(a.i(0)):new p.URL(a.i(0),A.e5().i(0))
n=A
s=3
return A.c(A.Q(p.fetch(o,null),t.m),$async$k5)
case 3:q=n.k4(d)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$k5,r)},
k4(a){var s=0,r=A.j(t.n),q,p,o
var $async$k4=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:p=A
o=A
s=3
return A.c(A.k_(a),$async$k4)
case 3:q=new p.d2(new o.k6(c))
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$k4,r)},
d2:function d2(a){this.a=a},
e7:function e7(a,b,c,d,e){var _=this
_.d=a
_.e=b
_.r=c
_.b=d
_.a=e},
h8:function h8(a,b){this.a=a
this.b=b
this.c=0},
oL(a){var s=J.a_(a.byteLength,8)
if(!s)throw A.a(A.M("Must be 8 in length",null))
s=v.G.Int32Array
return new A.jn(t.ha.a(A.cw(s,[a])))},
rJ(a){return B.f},
rK(a){var s=a.b
return new A.J(s.getInt32(0,!1),s.getInt32(4,!1),s.getInt32(8,!1))},
rL(a){var s=a.b
return new A.az(B.m.cb(A.nd(a.a,16,s.getInt32(12,!1))),s.getInt32(0,!1),s.getInt32(4,!1),s.getInt32(8,!1))},
jn:function jn(a){this.b=a},
aW:function aW(a,b,c){this.a=a
this.b=b
this.c=c},
Z:function Z(a,b,c,d,e){var _=this
_.c=a
_.d=b
_.a=c
_.b=d
_.$ti=e},
bb:function bb(){},
aE:function aE(){},
J:function J(a,b,c){this.a=a
this.b=b
this.c=c},
az:function az(a,b,c,d){var _=this
_.d=a
_.a=b
_.b=c
_.c=d},
h6(a){var s=0,r=A.j(t.ei),q,p,o,n,m,l,k,j,i
var $async$h6=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:k=t.m
s=3
return A.c(A.Q(A.hJ().getDirectory(),k),$async$h6)
case 3:j=c
i=$.eX().cM(0,a.root)
p=i.length,o=0
case 4:if(!(o<i.length)){s=6
break}s=7
return A.c(A.Q(j.getDirectoryHandle(i[o],{create:!0}),k),$async$h6)
case 7:j=c
case 5:i.length===p||(0,A.R)(i),++o
s=4
break
case 6:k=t.cT
p=A.oL(a.synchronizationBuffer)
n=a.communicationBuffer
m=A.oO(n,65536,2048)
l=v.G.Uint8Array
q=new A.e6(p,new A.aW(n,m,t.Z.a(A.cw(l,[n]))),j,A.a4(t.S,k),A.cN(k))
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$h6,r)},
hx:function hx(a,b,c){this.a=a
this.b=b
this.c=c},
e6:function e6(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=0
_.e=!1
_.f=d
_.r=e},
dd:function dd(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=!1
_.x=null},
fi(a,b){var s=0,r=A.j(t.bd),q,p,o,n,m,l
var $async$fi=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:p=t.N
o=new A.f1(a)
n=A.n3("dart-memory",null)
m=$.eU()
l=new A.bY(o,n,new A.dO(t.au),A.cN(p),A.a4(p,t.S),m,b)
s=3
return A.c(o.cs(),$async$fi)
case 3:s=4
return A.c(l.bu(),$async$fi)
case 4:q=l
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$fi,r)},
f1:function f1(a){this.a=null
this.b=a},
hX:function hX(a){this.a=a},
hU:function hU(a){this.a=a},
hY:function hY(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
hW:function hW(a,b){this.a=a
this.b=b},
hV:function hV(a,b){this.a=a
this.b=b},
kN:function kN(a,b,c){this.a=a
this.b=b
this.c=c},
kO:function kO(a,b){this.a=a
this.b=b},
hv:function hv(a,b){this.a=a
this.b=b},
bY:function bY(a,b,c,d,e,f,g){var _=this
_.d=a
_.e=!1
_.f=null
_.r=b
_.w=c
_.x=d
_.y=e
_.b=f
_.a=g},
iR:function iR(a){this.a=a},
iS:function iS(){},
ho:function ho(a,b,c){this.a=a
this.b=b
this.c=c},
l0:function l0(a,b){this.a=a
this.b=b},
a8:function a8(){},
cj:function cj(a,b){var _=this
_.w=a
_.d=b
_.c=_.b=_.a=null},
d8:function d8(a,b,c){var _=this
_.w=a
_.x=b
_.d=c
_.c=_.b=_.a=null},
cg:function cg(a,b,c){var _=this
_.w=a
_.x=b
_.d=c
_.c=_.b=_.a=null},
cs:function cs(a,b,c,d,e){var _=this
_.w=a
_.x=b
_.y=c
_.z=d
_.d=e
_.c=_.b=_.a=null},
fS(a){var s=0,r=A.j(t.cf),q,p,o,n,m,l,k,j,i
var $async$fS=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:i=A.hJ()
if(i==null)throw A.a(A.bC(1))
p=t.m
s=3
return A.c(A.Q(i.getDirectory(),p),$async$fS)
case 3:o=c
n=$.nY().cM(0,a),m=n.length,l=null,k=0
case 4:if(!(k<n.length)){s=6
break}s=7
return A.c(A.Q(o.getDirectoryHandle(n[k],{create:!0}),p),$async$fS)
case 7:j=c
case 5:n.length===m||(0,A.R)(n),++k,l=o,o=j
s=4
break
case 6:q=new A.aB(l,o)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$fS,r)},
fU(a,b,c){var s=0,r=A.j(t.gW),q,p
var $async$fU=A.k(function(d,e){if(d===1)return A.f(e,r)
for(;;)switch(s){case 0:if(A.hJ()==null)throw A.a(A.bC(1))
p=A
s=3
return A.c(A.fS(a),$async$fU)
case 3:q=p.fT(e.b,b,c)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$fU,r)},
fT(a,b,c){var s=0,r=A.j(t.gW),q,p,o,n,m,l,k,j,i,h,g
var $async$fT=A.k(function(d,e){if(d===1)return A.f(e,r)
for(;;)switch(s){case 0:j=new A.jv(a,b)
s=3
return A.c(j.$1("meta"),$async$fT)
case 3:i=e
i.truncate(2)
p=A.a4(t.v,t.m)
o=0
case 4:if(!(o<2)){s=6
break}n=B.U[o]
h=p
g=n
s=7
return A.c(j.$1(n.b),$async$fT)
case 7:h.p(0,g,e)
case 5:++o
s=4
break
case 6:m=new Uint8Array(2)
l=A.n3("dart-memory",null)
k=$.eU()
q=new A.cY(i,m,p,l,k,c)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$fT,r)},
cI:function cI(a,b,c){this.c=a
this.a=b
this.b=c},
cY:function cY(a,b,c,d,e,f){var _=this
_.d=a
_.e=b
_.f=c
_.r=d
_.b=e
_.a=f},
jv:function jv(a,b){this.a=a
this.b=b},
hC:function hC(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=0},
k_(a){var s=0,r=A.j(t.h2),q,p,o,n
var $async$k_=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:o=A.tB()
n=o.b
n===$&&A.O()
s=3
return A.c(A.k1(a,n),$async$k_)
case 3:p=c
n=o.c
n===$&&A.O()
q=o.a=new A.h7(n,o.d,p.exports)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$k_,r)},
at(a){var s,r,q
try{a.$0()
return 0}catch(r){q=A.W(r)
if(q instanceof A.aq){s=q
return s.a}else return 1}},
nn(a,b){var s,r=A.aF(a.buffer,b,null)
for(s=0;r[s]!==0;)++s
return s},
bE(a,b,c){var s=a.buffer
return B.m.cb(A.aF(s,b,c==null?A.nn(a,b):c))},
nm(a,b,c){var s
if(b===0)return null
s=a.buffer
return B.m.cb(A.aF(s,b,c==null?A.nn(a,b):c))},
p_(a,b,c){var s=new Uint8Array(c)
B.d.aF(s,0,A.aF(a.buffer,b,c))
return s},
tB(){var s=t.S
s=new A.l1(new A.ih(A.a4(s,t.dG),A.a4(s,t.b9),A.a4(s,t.l),A.a4(s,t.cG),A.a4(s,t.dW)))
s.fA()
return s},
h7:function h7(a,b,c){this.b=a
this.c=b
this.d=c},
l1:function l1(a){var _=this
_.c=_.b=_.a=$
_.d=a},
lh:function lh(a){this.a=a},
li:function li(a,b){this.a=a
this.b=b},
l8:function l8(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g},
lj:function lj(a,b){this.a=a
this.b=b},
l7:function l7(a,b,c){this.a=a
this.b=b
this.c=c},
lu:function lu(a,b){this.a=a
this.b=b},
l6:function l6(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
lF:function lF(a,b){this.a=a
this.b=b},
l5:function l5(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
lG:function lG(a,b){this.a=a
this.b=b},
lg:function lg(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
lH:function lH(a){this.a=a},
lf:function lf(a,b){this.a=a
this.b=b},
lI:function lI(a,b){this.a=a
this.b=b},
lJ:function lJ(a){this.a=a},
lK:function lK(a){this.a=a},
le:function le(a,b,c){this.a=a
this.b=b
this.c=c},
lL:function lL(a,b){this.a=a
this.b=b},
ld:function ld(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
lk:function lk(a,b){this.a=a
this.b=b},
lc:function lc(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
ll:function ll(a){this.a=a},
lb:function lb(a,b){this.a=a
this.b=b},
lm:function lm(a){this.a=a},
la:function la(a,b){this.a=a
this.b=b},
ln:function ln(a,b){this.a=a
this.b=b},
l9:function l9(a,b,c){this.a=a
this.b=b
this.c=c},
lo:function lo(a){this.a=a},
l4:function l4(a,b){this.a=a
this.b=b},
lp:function lp(a){this.a=a},
l3:function l3(a,b){this.a=a
this.b=b},
lq:function lq(a,b){this.a=a
this.b=b},
l2:function l2(a,b,c){this.a=a
this.b=b
this.c=c},
lr:function lr(a){this.a=a},
ls:function ls(a){this.a=a},
lt:function lt(a){this.a=a},
lv:function lv(a){this.a=a},
lw:function lw(a){this.a=a},
lx:function lx(a){this.a=a},
ly:function ly(a,b){this.a=a
this.b=b},
lz:function lz(a,b){this.a=a
this.b=b},
lA:function lA(a){this.a=a},
lB:function lB(a){this.a=a},
lC:function lC(a){this.a=a},
lD:function lD(a){this.a=a},
lE:function lE(a){this.a=a},
ih:function ih(a,b,c,d,e){var _=this
_.a=0
_.b=a
_.d=b
_.e=c
_.f=d
_.r=e
_.y=_.x=_.w=null},
fP:function fP(a,b,c){this.a=a
this.b=b
this.c=c},
mv(){var s=0,r=A.j(t.dX),q,p,o,n,m,l
var $async$mv=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:m=new v.G.MessageChannel()
l=$.mS()
s=l!=null?3:5
break
case 3:p=A.uO()
s=6
return A.c(l.eY(p),$async$mv)
case 6:o=b
s=4
break
case 5:o=null
p=null
case 4:n=A.pI(m.port2,p,o)
q=new A.aB({port:m.port1,lockName:p},n)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$mv,r)},
uO(){var s,r
for(s=0,r="channel-close-";s<16;++s)r+=A.aX(97+$.qK().bK(26))
return r.charCodeAt(0)==0?r:r},
pI(a,b,c){var s=null,r=new A.fX(t.gl),q=t.cb,p=A.jz(s,s,!1,q),o=A.jz(s,s,!1,q),n=A.ok(new A.as(o,A.D(o).h("as<1>")),new A.eA(p),!0,q)
r.a=n
q=A.ok(new A.as(p,A.D(p).h("as<1>")),new A.eA(o),!0,q)
r.b=q
a.start()
A.ag(a,"message",new A.mi(r),!1,t.m)
n=n.b
n===$&&A.O()
new A.as(n,A.D(n).h("as<1>")).iJ(new A.mj(a),new A.mk(a,c))
if(c==null&&b!=null)$.mS().eY(b).dO(new A.ml(r),t.P)
return q},
mi:function mi(a){this.a=a},
mj:function mj(a){this.a=a},
mk:function mk(a,b){this.a=a
this.b=b},
ml:function ml(a){this.a=a},
fN:function fN(){},
je:function je(a){this.a=a},
ii:function ii(){},
cf:function cf(){},
k9:function k9(a){this.a=a},
ka:function ka(a){this.a=a},
kb:function kb(a){this.a=a},
bt:function bt(a){this.a=a},
iw:function iw(a,b,c){this.a=a
this.b=b
this.c=c},
fz:function fz(a){this.a=!1
this.b=a},
j8:function j8(a,b){this.a=a
this.b=b},
j7:function j7(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
j6:function j6(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
rN(a){return A.oc(B.A,a)},
rR(a){return A.oc(B.o,a)},
rS(a){return A.nf(B.B,a)},
rQ(a){return A.nf(B.v,a)},
rM(a){return A.nf(B.z,a)},
rP(a){return new A.aU(A.r(A.z(a.d)),B.x)},
rO(a){return new A.aU(A.r(A.z(a.d)),B.C)},
n8(a){return $.qm().j(0,A.ah(a.t)).c.$1(a)},
rv(a){var s,r
for(s=0;s<5;++s){r=B.b6[s]
if(r.c===a)return r}throw A.a(A.M("Unknown FS implementation: "+a,null))},
rW(a){var s=A.rv(A.ah(a.s)),r=A.ah(a.d),q=A.jV(A.ah(a.u)),p=A.r(A.z(a.i)),o=A.nD(a.o)
if(o==null)o=null
return new A.c5(q,r,s,o===!0,a.a,p,null)},
rg(a){var s=A.r(A.z(a.i))
return new A.b6(A.a9(a.r),s,null)},
te(a){return new A.b_(A.a9(a.r))},
rh(a){var s=A.r(A.z(a.i)),r=a.r
return new A.bp(r,s,"d" in a?A.r(A.z(a.d)):null)},
rt(a){var s=B.T[A.r(A.z(a.f))],r=A.r(A.z(a.d))
return new A.bW(s,A.r(A.z(a.i)),r)},
ru(a){var s=A.r(A.z(a.d))
return new A.bX(A.r(A.z(a.i)),s)},
rr(a){var s=A.r(A.z(a.d)),r=A.r(A.z(a.i))
return new A.bV(t.dy.a(a.b),B.T[A.r(A.z(a.f))],r,s)},
tb(a){var s=A.r(A.z(a.i)),r=A.r(A.z(a.d)),q=A.nE(a.z)
q=q==null?null:A.r(q)
return new A.c9(A.ah(a.s),A.nj(t.c.a(a.p),t.dy.a(a.v)),q,A.aR(a.r),A.aR(a.c),s,r)},
t6(a){return new A.c8(A.r(A.z(a.i)),A.r(A.z(a.d)))},
t5(a){var s=A.r(A.z(a.i)),r=A.r(A.z(a.d))
return new A.c7(A.r(A.z(a.z)),s,r)},
r6(a){return new A.bP(A.r(A.z(a.i)),A.r(A.z(a.d)))},
rV(a){return new A.c4(A.r(A.z(a.i)),A.r(A.z(a.d)))},
tc(a){return new A.X(a.r,A.r(A.z(a.i)))},
rj(a){var s=A.r(A.z(a.i))
return new A.bq(A.a9(a.r),s)},
oU(a){var s,r,q,p,o,n,m,l,k,j=null
A:{if(a==null){s=j
r=B.am
break A}q=A.ct(a)
p=q?a:j
if(q){s=p
r=B.ah
break A}q=a instanceof A.U
o=q?a:j
if(q){s=v.G.BigInt(o.i(0))
r=B.ai
break A}q=typeof a=="number"
n=q?a:j
if(q){s=n
r=B.aj
break A}q=typeof a=="string"
m=q?a:j
if(q){s=m
r=B.ak
break A}q=t.p.b(a)
l=q?a:j
if(q){s=l
r=B.al
break A}q=A.dj(a)
k=q?a:j
if(q){s=k
r=B.an
break A}s=A.qa(a)
r=B.l}return new A.aB(r,s)},
nk(a){var s,r,q=[],p=a.length,o=new Uint8Array(p)
for(s=0;s<a.length;++s){r=A.oU(a[s])
o[s]=r.a.a
q.push(r.b)}return new A.aB(q,t.a.a(B.d.gaa(o)))},
nj(a,b){var s,r,q,p,o=b==null?null:A.aF(b,0,null),n=a.length,m=A.an(n,null,!1,t.X)
for(s=o!=null,r=0;r<n;++r){if(s){q=o[r]
p=q>=8?B.l:B.S[q]}else p=B.l
m[r]=p.eI(a[r])}return m},
t7(a){var s,r="c" in a?A.t8(a):null,q=A.r(A.z(a.i)),p=A.nD(a.x)
if(p==null)p=null
s=A.nE(a.y)
s=s==null?null:A.r(s)
if(s==null)s=0
return new A.aZ(r,p===!0,s,q)},
t9(a,a0,a1){var s,r,q,p,o,n,m,l,k,j,i,h=t.fk,g=A.n([],h),f=a1.a,e=f.length,d=a1.d,c=d.length,b=new Uint8Array(c*e)
for(c=t.X,s=0;s<d.length;++s){r=d[s]
q=A.an(r.length,null,!1,c)
for(p=s*e,o=0;o<e;++o){n=A.oU(r[o])
q[o]=n.b
b[p+o]=n.a.a}g.push(q)}m=t.a.a(B.d.gaa(b))
a.v=m
a0.push(m)
h=A.n([],h)
for(c=d.length,l=0;l<d.length;d.length===c||(0,A.R)(d),++l){p=[]
for(k=B.c.gt(d[l]);k.l();)p.push(A.qa(k.gm()))
h.push(p)}a.r=h
h=A.n([],t.s)
for(d=f.length,l=0;l<f.length;f.length===d||(0,A.R)(f),++l)h.push(f[l])
a.c=h
j=a1.b
if(j!=null){h=A.n([],t.G)
for(f=j.length,l=0;l<j.length;j.length===f||(0,A.R)(j),++l){i=j[l]
h.push(i==null?null:i)}a.n=h}else a.n=null},
t8(a){var s,r,q,p,o,n,m,l,k,j,i,h=t.s,g=A.n([],h),f=t.c,e=f.a(a.c),d=B.c.gt(e)
while(d.l())g.push(A.ah(d.gm()))
s=a.n
if(s!=null){h=A.n([],h)
f.a(s)
d=B.c.gt(s)
while(d.l())h.push(A.ah(d.gm()))
r=h}else r=null
q=a.v
A:{h=null
if(q!=null){h=A.aF(t.a.a(q),0,null)
break A}break A}p=A.n([],t.E)
e=f.a(a.r)
d=B.c.gt(e)
o=h!=null
n=0
while(d.l()){m=[]
e=f.a(d.gm())
l=B.c.gt(e)
while(l.l()){k=l.gm()
if(o){j=h[n]
i=j>=8?B.l:B.S[j]}else i=B.l
m.push(i.eI(k));++n}p.push(m)}return A.oM(g,r,p)},
rm(a){return A.rl(a)},
rl(a){var s,r,q=null
if("s" in a){s=A.r(A.z(a.s))
A:{if(0===s){r=A.rn(t.c.a(a.r))
break A}if(1===s){r=B.K
break A}r=q
break A}q=r}return new A.br(A.ah(a.e),q,A.r(A.z(a.i)))},
rn(a){var s,r,q,p,o=null,n=a.length>=7,m=o,l=o,k=o,j=o,i=o,h=o
if(n){s=a[0]
m=a[1]
l=a[2]
k=a[3]
j=a[4]
i=a[5]
h=a[6]}else s=o
if(!n)throw A.a(A.L("Pattern matching error"))
n=new A.iC()
l=A.r(A.z(l))
A.ah(s)
r=n.$1(m)
q=n.$1(j)
p=i!=null&&h!=null?A.nj(t.c.a(i),t.a.a(h)):o
return new A.ca(s,r,l,o,n.$1(k),q,p)},
ro(a){var s,r,q,p,o,n,m=null,l=a.r
A:{if(l==null){s=m
break A}s=A.nk(l)
break A}r=a.b
if(r==null)r=m
q=a.e
if(q==null)q=m
p=a.f
if(p==null)p=m
o=s==null
n=o?m:s.a
s=o?m:s.b
return[a.a,r,a.c,q,p,n,s]},
nf(a,b){return new A.cb(A.aR(b.a),a,A.r(A.z(b.i)),A.r(A.z(b.d)))},
oc(a,b){var s=A.r(A.z(b.i)),r=A.pH(b.d)
return new A.b5(a,r==null?null:r,s,null)},
rc(a){var s,r,q,p,o,n,m=A.n([],t.gQ),l=t.c.a(a.a),k=t.Y.b(l)?l:new A.bO(l,A.ac(l).h("bO<1,o>"))
for(s=J.au(k),r=0;r<s.gk(k)/2;++r){q=r*2
m.push(new A.aB(A.oi(B.b7,s.j(k,q)),s.j(k,q+1)))}s=A.aR(a.b)
q=A.aR(a.c)
p=A.aR(a.d)
o=A.aR(a.e)
n=A.aR(a.f)
return new A.bR(m,s,q,A.aR(a.g),p,o,n)},
ti(a){return new A.bB(new A.aG(B.b4[A.r(A.z(a.k))],A.ah(a.u),A.r(A.z(a.r))),A.r(A.z(a.d)))},
r1(a){return new A.bn(A.r(A.z(a.i)))},
w:function w(a,b,c,d){var _=this
_.c=a
_.a=b
_.b=c
_.$ti=d},
A:function A(){},
j5:function j5(a){this.a=a},
j4:function j4(a){this.a=a},
dT:function dT(){},
jm:function jm(){},
cW:function cW(){},
ak:function ak(){},
bs:function bs(a,b,c){this.c=a
this.a=b
this.b=c},
c5:function c5(a,b,c,d,e,f,g){var _=this
_.c=a
_.d=b
_.e=c
_.f=d
_.r=e
_.a=f
_.b=g},
b6:function b6(a,b,c){this.c=a
this.a=b
this.b=c},
b_:function b_(a){this.a=a},
bp:function bp(a,b,c){this.c=a
this.a=b
this.b=c},
bW:function bW(a,b,c){this.c=a
this.a=b
this.b=c},
bX:function bX(a,b){this.a=a
this.b=b},
bV:function bV(a,b,c,d){var _=this
_.c=a
_.d=b
_.a=c
_.b=d},
c9:function c9(a,b,c,d,e,f,g){var _=this
_.c=a
_.d=b
_.e=c
_.f=d
_.r=e
_.a=f
_.b=g},
c8:function c8(a,b){this.a=a
this.b=b},
c7:function c7(a,b,c){this.c=a
this.a=b
this.b=c},
bP:function bP(a,b){this.a=a
this.b=b},
c4:function c4(a,b){this.a=a
this.b=b},
X:function X(a,b){this.b=a
this.a=b},
bq:function bq(a,b){this.b=a
this.a=b},
aQ:function aQ(a,b){this.a=a
this.b=b},
aZ:function aZ(a,b,c,d){var _=this
_.b=a
_.c=b
_.d=c
_.a=d},
br:function br(a,b,c){this.b=a
this.c=b
this.a=c},
iC:function iC(){},
cb:function cb(a,b,c,d){var _=this
_.c=a
_.d=b
_.a=c
_.b=d},
b5:function b5(a,b,c,d){var _=this
_.c=a
_.d=b
_.a=c
_.b=d},
bR:function bR(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g},
bB:function bB(a,b){this.a=a
this.b=b},
aU:function aU(a,b){this.a=a
this.b=b},
bn:function bn(a){this.a=a},
mu(){var s=0,r=A.j(t.y),q,p=2,o=[],n,m,l,k,j
var $async$mu=A.k(function(a,b){if(a===1){o.push(b)
s=p}for(;;)switch(s){case 0:k=v.G
if(!("indexedDB" in k)||!("FileReader" in k)){q=!1
s=1
break}n=A.a9(k.indexedDB)
p=4
s=7
return A.c(A.re(n.open("drift_mock_db"),t.m),$async$mu)
case 7:m=b
m.close()
n.deleteDatabase("drift_mock_db")
p=2
s=6
break
case 4:p=3
j=o.pop()
q=!1
s=1
break
s=6
break
case 3:s=2
break
case 6:q=!0
s=1
break
case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$mu,r)},
ms(a){return A.v5(a)},
v5(a){var s=0,r=A.j(t.y),q,p=2,o=[],n,m,l,k,j,i
var $async$ms=A.k(function(b,c){if(b===1){o.push(c)
s=p}for(;;)switch(s){case 0:j={}
j.a=null
p=4
n=A.a9(v.G.indexedDB)
m=n.open(a,1)
m.onupgradeneeded=A.aK(new A.mt(j,m))
s=7
return A.c(A.rd(m,t.m),$async$ms)
case 7:l=c
if(j.a==null)j.a=!0
l.close()
p=2
s=6
break
case 4:p=3
i=o.pop()
s=6
break
case 3:s=2
break
case 6:j=j.a
q=j===!0
s=1
break
case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$ms,r)},
ds(){var s=0,r=A.j(t.Y),q,p=2,o=[],n=[],m,l,k,j,i,h,g
var $async$ds=A.k(function(a,b){if(a===1){o.push(b)
s=p}for(;;)switch(s){case 0:h=A.hJ()
if(h==null){q=B.u
s=1
break}j=t.m
s=3
return A.c(A.Q(h.getDirectory(),j),$async$ds)
case 3:m=b
p=5
s=8
return A.c(A.Q(m.getDirectoryHandle("drift_db",{create:!1}),j),$async$ds)
case 8:m=b
p=2
s=7
break
case 5:p=4
g=o.pop()
q=B.u
s=1
break
s=7
break
case 4:s=2
break
case 7:l=A.n([],t.s)
j=new A.cp(A.cx(A.rs(m),"stream",t.K))
p=9
case 12:s=14
return A.c(j.l(),$async$ds)
case 14:if(!b){s=13
break}k=j.gm()
if(J.a_(k.kind,"directory"))J.o_(l,k.name)
s=12
break
case 13:n.push(11)
s=10
break
case 9:n=[2]
case 10:p=2
s=15
return A.c(j.B(),$async$ds)
case 15:s=n.pop()
break
case 11:q=l
s=1
break
case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$ds,r)},
rd(a,b){var s=new A.m($.q,b.h("m<0>")),r=new A.H(s,b.h("H<0>")),q=t.m
A.ag(a,"success",new A.i2(r,a,b),!1,q)
A.ag(a,"error",new A.i3(r,a),!1,q)
return s},
re(a,b){var s=new A.m($.q,b.h("m<0>")),r=new A.H(s,b.h("H<0>")),q=t.m
A.ag(a,"success",new A.i6(r,a,b),!1,q)
A.ag(a,"error",new A.i7(r,a),!1,q)
A.ag(a,"blocked",new A.i8(r,a),!1,q)
return s},
mt:function mt(a,b){this.a=a
this.b=b},
i2:function i2(a,b,c){this.a=a
this.b=b
this.c=c},
i3:function i3(a,b){this.a=a
this.b=b},
i6:function i6(a,b,c){this.a=a
this.b=b
this.c=c},
i7:function i7(a,b){this.a=a
this.b=b},
i8:function i8(a,b){this.a=a
this.b=b},
dF:function dF(a,b){this.a=a
this.b=b},
bz:function bz(a,b){this.a=a
this.b=b},
cV:function cV(a){this.a=a},
bm:function bm(a){this.a=a},
tn(){var s=v.G
if(A.oo(s,"DedicatedWorkerGlobalScope"))return new A.fc(s)
else return new A.jp(s)},
pd(a,b){var s=A.n([],t.W),r=b==null?a.b:b
return new A.d5(a,r,new A.eB(),new A.eB(),new A.eB(),s)},
ty(a,b,c){var s=t.S
s=new A.ef(c,A.n([],t.bZ),a,A.a4(s,t.eR),A.a4(s,t.m))
s.fv(a)
s.fz(a,b,c)
return s},
pM(a){var s
switch(a.a){case 0:s="/database"
break
case 1:s="/database-journal"
break
default:s=null}return s},
cy(){var s=0,r=A.j(t.c9),q,p=2,o=[],n=[],m,l,k,j,i,h,g,f,e,d,c,b
var $async$cy=A.k(function(a,a0){if(a===1){o.push(a0)
s=p}for(;;)switch(s){case 0:c=A.hJ()
if(c==null){q=B.D
s=1
break}m=null
l=null
k=null
j=!1
p=4
e=t.m
s=7
return A.c(A.Q(c.getDirectory(),e),$async$cy)
case 7:m=a0
s=8
return A.c(A.Q(m.getFileHandle("_drift_feature_detection",{create:!0}),e),$async$cy)
case 8:l=a0
s=9
return A.c(A.eR(l),$async$cy)
case 9:i=a0
h=null
g=null
h=i.a
g=i.b
j=h
k=g
f=A.fq(k,"getSize",null,null,null,null)
s=typeof f==="object"?10:11
break
case 10:s=12
return A.c(A.Q(A.a9(f),t.X),$async$cy)
case 12:q=B.D
n=[1]
s=5
break
case 11:h=j
q=new A.ev(!0,h)
n=[1]
s=5
break
n.push(6)
s=5
break
case 4:p=3
b=o.pop()
q=B.D
n=[1]
s=5
break
n.push(6)
s=5
break
case 3:n=[2]
case 5:p=2
if(k!=null)k.close()
s=m!=null&&l!=null?13:14
break
case 13:s=15
return A.c(A.mY(m,"_drift_feature_detection"),$async$cy)
case 15:case 14:s=n.pop()
break
case 6:case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$cy,r)},
eR(a){return A.uX(a)},
uX(a){var s=0,r=A.j(t.f9),q,p=2,o=[],n,m,l,k,j,i
var $async$eR=A.k(function(b,c){if(b===1){o.push(c)
s=p}for(;;)switch(s){case 0:j=null
p=4
l=t.m
s=7
return A.c(A.Q(a.createSyncAccessHandle({mode:"readwrite-unsafe"}),l),$async$eR)
case 7:j=c
s=8
return A.c(A.Q(a.createSyncAccessHandle({mode:"readwrite-unsafe"}),l),$async$eR)
case 8:n=c
n.close()
l=j
q=new A.aB(!0,l)
s=1
break
p=2
s=6
break
case 4:p=3
i=o.pop()
l=j
if(l!=null)l.close()
s=9
return A.c(A.Q(a.createSyncAccessHandle(),t.m),$async$eR)
case 9:m=c
q=new A.aB(!1,m)
s=1
break
s=6
break
case 3:s=2
break
case 6:case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$eR,r)},
kd:function kd(){},
fc:function fc(a){this.a=a},
iA:function iA(){},
jp:function jp(a){this.a=a},
jt:function jt(a){this.a=a},
ju:function ju(a,b,c){this.a=a
this.b=b
this.c=c},
js:function js(a){this.a=a},
jq:function jq(a){this.a=a},
jr:function jr(a){this.a=a},
eB:function eB(){this.a=null},
d5:function d5(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=null
_.r=1
_.w=f},
kC:function kC(a){this.a=a},
kG:function kG(a,b){this.a=a
this.b=b},
kD:function kD(a,b){this.a=a
this.b=b},
kE:function kE(a){this.a=a},
kF:function kF(a,b){this.a=a
this.b=b},
ef:function ef(a,b,c,d,e){var _=this
_.e=a
_.f=b
_.a=c
_.b=0
_.c=d
_.d=e},
ku:function ku(a){this.a=a},
kv:function kv(a,b){this.a=a
this.b=b},
kz:function kz(a,b){this.a=a
this.b=b},
ky:function ky(a,b){this.a=a
this.b=b},
kA:function kA(a,b){this.a=a
this.b=b},
kx:function kx(a,b){this.a=a
this.b=b},
kB:function kB(a,b){this.a=a
this.b=b},
kw:function kw(a,b){this.a=a
this.b=b},
kt:function kt(a){this.a=a},
fa:function fa(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=1
_.z=_.y=_.x=_.w=null},
iz:function iz(a){this.a=a},
iy:function iy(a){this.a=a},
ix:function ix(a,b){this.a=a
this.b=b},
ke:function ke(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=0
_.e=d
_.f=0
_.w=_.r=null
_.x=e
_.z=null},
kf:function kf(a,b){this.a=a
this.b=b},
kg:function kg(a,b){this.a=a
this.b=b},
kh:function kh(a){this.a=a},
th(a){var s={},r=A.n([],t.ey),q=A.cN(t.N)
s.a=A.n([],t.w)
return new A.bh(!0,new A.jM(new A.jH(s,r,a,new A.jN(q),new A.jK(r,q),new A.jL(q)),new A.jO(s,r)),t.aT)},
jN:function jN(a){this.a=a},
jK:function jK(a,b){this.a=a
this.b=b},
jL:function jL(a){this.a=a},
jH:function jH(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
jI:function jI(a){this.a=a},
jJ:function jJ(a){this.a=a},
jO:function jO(a,b){this.a=a
this.b=b},
jM:function jM(a,b){this.a=a
this.b=b},
jG:function jG(a,b){this.a=a
this.b=b},
cq:function cq(a,b){this.a=a
this.b=b},
oe(a,b,c){var s=b==null?"":b,r=A.nk(c)
return{rawKind:a.b,rawSql:s,rawParameters:r.a,typeInfo:r.b}},
bo:function bo(a,b){this.a=a
this.b=b},
tz(){return new A.d6()},
f_:function f_(){},
f0:function f0(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
hS:function hS(a,b){this.a=a
this.b=b},
hT:function hT(a,b,c){this.a=a
this.b=b
this.c=c},
d6:function d6(){this.a=!1
this.c=null},
ok(a,b,c,d){var s,r={}
r.a=a
s=new A.dI(d.h("dI<0>"))
s.fu(b,!0,r,d)
return s},
dI:function dI(a){var _=this
_.b=_.a=$
_.c=null
_.d=!1
_.$ti=a},
iQ:function iQ(a,b){this.a=a
this.b=b},
iP:function iP(a){this.a=a},
hl:function hl(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.e=_.d=!1
_.r=_.f=null
_.w=d},
fX:function fX(a){this.b=this.a=$
this.$ti=a},
e2:function e2(){},
d_:function d_(){},
hp:function hp(){},
b1:function b1(a,b){this.a=a
this.b=b},
jf:function jf(){},
ie:function ie(){},
jZ:function jZ(){},
ag(a,b,c,d,e){var s
if(c==null)s=null
else{s=A.q2(new A.kL(c),t.m)
s=s==null?null:A.aK(s)}s=new A.d9(a,b,s,!1,e.h("d9<0>"))
s.di()
return s},
q2(a,b){var s=$.q
if(s===B.e)return a
return s.eD(a,b)},
mW:function mW(a,b){this.a=a
this.$ti=b},
ci:function ci(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.$ti=d},
d9:function d9(a,b,c,d,e){var _=this
_.a=0
_.b=a
_.c=b
_.d=c
_.e=d
_.$ti=e},
kL:function kL(a){this.a=a},
kM:function kM(a){this.a=a},
vt(a){if(typeof dartPrint=="function"){dartPrint(a)
return}if(typeof console=="object"&&typeof console.log!="undefined"){console.log(a)
return}if(typeof print=="function"){print(a)
return}throw"Unable to print message: "+String(a)},
rD(a,b){return b in a},
fq(a,b,c,d,e,f){var s
if(c==null)return a[b]()
else if(d==null)return a[b](c)
else if(e==null)return a[b](c,d)
else{s=a[b](c,d,e)
return s}},
va(){var s,r,q,p,o=null
try{o=A.e5()}catch(s){if(t.g8.b(A.W(s))){r=$.mn
if(r!=null)return r
throw s}else throw s}if(J.a_(o,$.pJ)){r=$.mn
r.toString
return r}$.pJ=o
if($.nU()===$.eV())r=$.mn=o.f_(".").i(0)
else{q=o.dP()
p=q.length-1
r=$.mn=p===0?q:B.a.n(q,0,p)}return r},
q8(a){var s
if(!(a>=65&&a<=90))s=a>=97&&a<=122
else s=!0
return s},
vc(a,b){var s,r,q=null,p=a.length,o=b+2
if(p<o)return q
if(!A.q8(a.charCodeAt(b)))return q
s=b+1
if(a.charCodeAt(s)!==58){r=b+4
if(p<r)return q
if(B.a.n(a,s,r).toLowerCase()!=="%3a")return q
b=o}s=b+2
if(p===s)return s
if(a.charCodeAt(s)!==47)return q
return b+3},
vr(){var s=A.n([],t.bj),r=A.ov(t.ge),q=A.tn()
new A.ke(q,new A.jc(),s,A.a4(t.S,t.eX),new A.fz(r)).aB()},
nL(a,b,c,d,e,f){var s,r=null,q=b.a,p=b.b,o=q.d,n=o.sqlite3_extended_errcode(p),m=o.sqlite3_error_offset,l=m==null?r:A.r(A.z(m.call(null,p)))
if(l==null)l=-1
A:{if(l<0){m=r
break A}m=l
break A}s=a.b
return new A.ca(A.bE(q.b,o.sqlite3_errmsg(p),r),A.bE(s.b,s.d.sqlite3_errstr(n),r)+" (code "+A.y(n)+")",c,m,d,e,f)},
eT(a,b,c,d,e){throw A.a(A.nL(a.a,a.b,b,c,d,e))},
o3(a){if(a.ab(0,$.qN())<0||a.ab(0,$.qM())>0)throw A.a(A.mX("BigInt value exceeds the range of 64 bits"))
return a},
t4(a){var s,r=a.a,q=a.b,p=r.d,o=p.sqlite3_value_type(q)
A:{s=null
if(1===o){r=A.r(v.G.Number(p.sqlite3_value_int64(q)))
break A}if(2===o){r=p.sqlite3_value_double(q)
break A}if(3===o){o=p.sqlite3_value_bytes(q)
o=A.bE(r.b,p.sqlite3_value_text(q),o)
r=o
break A}if(4===o){o=p.sqlite3_value_bytes(q)
o=A.p_(r.b,p.sqlite3_value_blob(q),o)
r=o
break A}r=s
break A}return r},
n2(a,b){var s,r
for(s=b,r=0;r<16;++r)s+=A.aX("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ012346789".charCodeAt(a.bK(61)))
return s.charCodeAt(0)==0?s:s},
jk(a){var s=0,r=A.j(t.J),q
var $async$jk=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:s=3
return A.c(A.Q(a.arrayBuffer(),t.a),$async$jk)
case 3:q=c
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$jk,r)},
oO(a,b,c){var s=v.G.DataView,r=[a]
r.push(b)
r.push(c)
return t.gT.a(A.cw(s,r))},
nd(a,b,c){var s=v.G.Uint8Array,r=[a]
r.push(b)
r.push(c)
return t.Z.a(A.cw(s,r))},
r3(a,b){v.G.Atomics.notify(a,b,1/0)}},B={}
var w=[A,J,B]
var $={}
A.n4.prototype={}
J.fl.prototype={
a3(a,b){return a===b},
gF(a){return A.dW(a)},
i(a){return"Instance of '"+A.fM(a)+"'"},
gS(a){return A.cA(A.nG(this))}}
J.fo.prototype={
i(a){return String(a)},
gF(a){return a?519018:218159},
gS(a){return A.cA(t.y)},
$iF:1,
$iad:1}
J.dL.prototype={
a3(a,b){return null==b},
i(a){return"null"},
gF(a){return 0},
$iF:1,
$iB:1}
J.P.prototype={$ie:1}
J.bv.prototype={
gF(a){return 0},
i(a){return String(a)}}
J.fL.prototype={}
J.ce.prototype={}
J.ax.prototype={
i(a){var s=a[$.cD()]
if(s==null)return this.fp(a)
return"JavaScript function for "+J.bl(s)}}
J.ai.prototype={
gF(a){return 0},
i(a){return String(a)}}
J.cL.prototype={
gF(a){return 0},
i(a){return String(a)}}
J.t.prototype={
E(a,b){a.$flags&1&&A.v(a,29)
a.push(b)},
cw(a,b){var s
a.$flags&1&&A.v(a,"removeAt",1)
s=a.length
if(b>=s)throw A.a(A.nb(b,null))
return a.splice(b,1)[0]},
iC(a,b,c){var s
a.$flags&1&&A.v(a,"insert",2)
s=a.length
if(b>s)throw A.a(A.nb(b,null))
a.splice(b,0,c)},
dB(a,b,c){var s,r
a.$flags&1&&A.v(a,"insertAll",2)
A.t3(b,0,a.length,"index")
if(!t.O.b(c))c=J.r0(c)
s=J.aw(c)
a.length=a.length+s
r=b+s
this.H(a,r,a.length,a,b)
this.a8(a,b,r,c)},
eV(a){a.$flags&1&&A.v(a,"removeLast",1)
if(a.length===0)throw A.a(A.eS(a,-1))
return a.pop()},
u(a,b){var s
a.$flags&1&&A.v(a,"remove",1)
for(s=0;s<a.length;++s)if(J.a_(a[s],b)){a.splice(s,1)
return!0}return!1},
am(a,b){var s
a.$flags&1&&A.v(a,"addAll",2)
if(Array.isArray(b)){this.fE(a,b)
return}for(s=J.ae(b);s.l();)a.push(s.gm())},
fE(a,b){var s,r=b.length
if(r===0)return
if(a===b)throw A.a(A.a5(a))
for(s=0;s<r;++s)a.push(b[s])},
aw(a){a.$flags&1&&A.v(a,"clear","clear")
a.length=0},
Z(a,b){var s,r=a.length
for(s=0;s<r;++s){b.$1(a[s])
if(a.length!==r)throw A.a(A.a5(a))}},
aR(a,b,c){return new A.aa(a,b,A.ac(a).h("@<1>").X(c).h("aa<1,2>"))},
bd(a,b){var s,r=A.an(a.length,"",!1,t.N)
for(s=0;s<a.length;++s)r[s]=A.y(a[s])
return r.join(b)},
f2(a,b){return A.e3(a,0,A.cx(b,"count",t.S),A.ac(a).c)},
ad(a,b){return A.e3(a,b,null,A.ac(a).c)},
ik(a,b){var s,r,q=a.length
for(s=0;s<q;++s){r=a[s]
if(b.$1(r))return r
if(a.length!==q)throw A.a(A.a5(a))}throw A.a(A.fm())},
M(a,b){return a[b]},
cR(a,b,c){var s=a.length
if(b>s)throw A.a(A.S(b,0,s,"start",null))
if(c<b||c>s)throw A.a(A.S(c,b,s,"end",null))
if(b===c)return A.n([],A.ac(a))
return A.n(a.slice(b,c),A.ac(a))},
gaA(a){if(a.length>0)return a[0]
throw A.a(A.fm())},
gap(a){var s=a.length
if(s>0)return a[s-1]
throw A.a(A.fm())},
H(a,b,c,d,e){var s,r,q,p,o
a.$flags&2&&A.v(a,5)
A.c6(b,c,a.length)
s=c-b
if(s===0)return
A.ap(e,"skipCount")
if(t.j.b(d)){r=d
q=e}else{r=J.hN(d,e).bj(0,!1)
q=0}p=J.au(r)
if(q+s>p.gk(r))throw A.a(A.on())
if(q<b)for(o=s-1;o>=0;--o)a[b+o]=p.j(r,q+o)
else for(o=0;o<s;++o)a[b+o]=p.j(r,q+o)},
a8(a,b,c,d){return this.H(a,b,c,d,0)},
fl(a,b){var s,r,q,p,o
a.$flags&2&&A.v(a,"sort")
s=a.length
if(s<2)return
if(b==null)b=J.uw()
if(s===2){r=a[0]
q=a[1]
if(b.$2(r,q)>0){a[0]=q
a[1]=r}return}p=0
if(A.ac(a).c.b(null))for(o=0;o<a.length;++o)if(a[o]===void 0){a[o]=null;++p}a.sort(A.cz(b,2))
if(p>0)this.hA(a,p)},
fk(a){return this.fl(a,null)},
hA(a,b){var s,r=a.length
for(;s=r-1,r>0;r=s)if(a[s]===null){a[s]=void 0;--b
if(b===0)break}},
dF(a,b){var s,r=a.length,q=r-1
if(q<0)return-1
q<r
for(s=q;s>=0;--s)if(J.a_(a[s],b))return s
return-1},
a5(a,b){var s
for(s=0;s<a.length;++s)if(J.a_(a[s],b))return!0
return!1},
gv(a){return a.length===0},
gao(a){return a.length!==0},
i(a){return A.iX(a,"[","]")},
bj(a,b){var s=A.n(a.slice(0),A.ac(a))
return s},
f5(a){return this.bj(a,!0)},
gt(a){return new J.cG(a,a.length,A.ac(a).h("cG<1>"))},
gF(a){return A.dW(a)},
gk(a){return a.length},
j(a,b){if(!(b>=0&&b<a.length))throw A.a(A.eS(a,b))
return a[b]},
p(a,b,c){a.$flags&2&&A.v(a)
if(!(b>=0&&b<a.length))throw A.a(A.eS(a,b))
a[b]=c},
$ip:1,
$id:1,
$iu:1}
J.fn.prototype={
ja(a){var s,r,q
if(!Array.isArray(a))return null
s=a.$flags|0
if((s&4)!==0)r="const, "
else if((s&2)!==0)r="unmodifiable, "
else r=(s&1)!==0?"fixed, ":""
q="Instance of '"+A.fM(a)+"'"
if(r==="")return q
return q+" ("+r+"length: "+a.length+")"}}
J.iY.prototype={}
J.cG.prototype={
gm(){var s=this.d
return s==null?this.$ti.c.a(s):s},
l(){var s,r=this,q=r.a,p=q.length
if(r.b!==p)throw A.a(A.R(q))
s=r.c
if(s>=p){r.d=null
return!1}r.d=q[s]
r.c=s+1
return!0}}
J.cK.prototype={
ab(a,b){var s
if(a<b)return-1
else if(a>b)return 1
else if(a===b){if(a===0){s=this.gdE(b)
if(this.gdE(a)===s)return 0
if(this.gdE(a))return-1
return 1}return 0}else if(isNaN(a)){if(isNaN(b))return 0
return 1}else return-1},
gdE(a){return a===0?1/a<0:a<0},
f3(a){var s
if(a>=-2147483648&&a<=2147483647)return a|0
if(isFinite(a)){s=a<0?Math.ceil(a):Math.floor(a)
return s+0}throw A.a(A.Y(""+a+".toInt()"))},
i6(a){var s,r
if(a>=0){if(a<=2147483647){s=a|0
return a===s?s:s+1}}else if(a>=-2147483648)return a|0
r=Math.ceil(a)
if(isFinite(r))return r
throw A.a(A.Y(""+a+".ceil()"))},
j8(a,b){var s,r,q,p
if(b<2||b>36)throw A.a(A.S(b,2,36,"radix",null))
s=a.toString(b)
if(s.charCodeAt(s.length-1)!==41)return s
r=/^([\da-z]+)(?:\.([\da-z]+))?\(e\+(\d+)\)$/.exec(s)
if(r==null)A.C(A.Y("Unexpected toString result: "+s))
s=r[1]
q=+r[3]
p=r[2]
if(p!=null){s+=p
q-=p.length}return s+B.a.bn("0",q)},
i(a){if(a===0&&1/a<0)return"-0.0"
else return""+a},
gF(a){var s,r,q,p,o=a|0
if(a===o)return o&536870911
s=Math.abs(a)
r=Math.log(s)/0.6931471805599453|0
q=Math.pow(2,r)
p=s<1?s/q:q/s
return((p*9007199254740992|0)+(p*3542243181176521|0))*599197+r*1259&536870911},
a7(a,b){var s=a%b
if(s===0)return 0
if(s>0)return s
return s+b},
ft(a,b){if((a|0)===a)if(b>=1||b<-1)return a/b|0
return this.eq(a,b)},
K(a,b){return(a|0)===a?a/b|0:this.eq(a,b)},
eq(a,b){var s=a/b
if(s>=-2147483648&&s<=2147483647)return s|0
if(s>0){if(s!==1/0)return Math.floor(s)}else if(s>-1/0)return Math.ceil(s)
throw A.a(A.Y("Result of truncating division is "+A.y(s)+": "+A.y(a)+" ~/ "+b))},
aG(a,b){if(b<0)throw A.a(A.dq(b))
return b>31?0:a<<b>>>0},
aZ(a,b){var s
if(b<0)throw A.a(A.dq(b))
if(a>0)s=this.dh(a,b)
else{s=b>31?31:b
s=a>>s>>>0}return s},
I(a,b){var s
if(a>0)s=this.dh(a,b)
else{s=b>31?31:b
s=a>>s>>>0}return s},
hI(a,b){if(0>b)throw A.a(A.dq(b))
return this.dh(a,b)},
dh(a,b){return b>31?0:a>>>b},
gS(a){return A.cA(t.o)},
$iI:1}
J.dK.prototype={
geE(a){var s,r=a<0?-a-1:a,q=r
for(s=32;q>=4294967296;){q=this.K(q,4294967296)
s+=32}return s-Math.clz32(q)},
gS(a){return A.cA(t.S)},
$iF:1,
$ib:1}
J.fp.prototype={
gS(a){return A.cA(t.i)},
$iF:1}
J.bu.prototype={
i7(a,b){if(b<0)throw A.a(A.eS(a,b))
if(b>=a.length)A.C(A.eS(a,b))
return a.charCodeAt(b)},
eA(a,b){return new A.hD(b,a,0)},
eK(a,b){var s=b.length,r=a.length
if(s>r)return!1
return b===this.T(a,r-s)},
aT(a,b,c,d){var s=A.c6(b,c,a.length)
return a.substring(0,b)+d+a.substring(s)},
D(a,b,c){var s
if(c<0||c>a.length)throw A.a(A.S(c,0,a.length,null,null))
s=c+b.length
if(s>a.length)return!1
return b===a.substring(c,s)},
A(a,b){return this.D(a,b,0)},
n(a,b,c){return a.substring(b,A.c6(b,c,a.length))},
T(a,b){return this.n(a,b,null)},
bn(a,b){var s,r
if(0>=b)return""
if(b===1||a.length===0)return a
if(b!==b>>>0)throw A.a(B.aO)
for(s=a,r="";;){if((b&1)===1)r=s+r
b=b>>>1
if(b===0)break
s+=s}return r},
eR(a,b,c){var s=b-a.length
if(s<=0)return a
return this.bn(c,s)+a},
aP(a,b,c){var s
if(c<0||c>a.length)throw A.a(A.S(c,0,a.length,null,null))
s=a.indexOf(b,c)
return s},
iB(a,b){return this.aP(a,b,0)},
eP(a,b,c){var s,r
if(c==null)c=a.length
else if(c<0||c>a.length)throw A.a(A.S(c,0,a.length,null,null))
s=b.length
r=a.length
if(c+s>r)c=r-s
return a.lastIndexOf(b,c)},
dF(a,b){return this.eP(a,b,null)},
a5(a,b){return A.vV(a,b,0)},
ab(a,b){var s
if(a===b)s=0
else s=a<b?-1:1
return s},
i(a){return a},
gF(a){var s,r,q
for(s=a.length,r=0,q=0;q<s;++q){r=r+a.charCodeAt(q)&536870911
r=r+((r&524287)<<10)&536870911
r^=r>>6}r=r+((r&67108863)<<3)&536870911
r^=r>>11
return r+((r&16383)<<15)&536870911},
gS(a){return A.cA(t.N)},
gk(a){return a.length},
$iF:1,
$io:1}
A.bH.prototype={
gt(a){return new A.f5(J.ae(this.gav()),A.D(this).h("f5<1,2>"))},
gk(a){return J.aw(this.gav())},
gv(a){return J.mU(this.gav())},
gao(a){return J.qW(this.gav())},
ad(a,b){var s=A.D(this)
return A.o9(J.hN(this.gav(),b),s.c,s.y[1])},
M(a,b){return A.D(this).y[1].a(J.hM(this.gav(),b))},
i(a){return J.bl(this.gav())}}
A.f5.prototype={
l(){return this.a.l()},
gm(){return this.$ti.y[1].a(this.a.gm())}}
A.bN.prototype={
gav(){return this.a}}
A.eh.prototype={$ip:1}
A.ee.prototype={
j(a,b){return this.$ti.y[1].a(J.qP(this.a,b))},
p(a,b,c){J.nZ(this.a,b,this.$ti.c.a(c))},
H(a,b,c,d,e){var s=this.$ti
J.qY(this.a,b,c,A.o9(d,s.y[1],s.c),e)},
a8(a,b,c,d){return this.H(0,b,c,d,0)},
$ip:1,
$iu:1}
A.bO.prototype={
gav(){return this.a}}
A.c_.prototype={
i(a){return"LateInitializationError: "+this.a}}
A.f6.prototype={
gk(a){return this.a.length},
j(a,b){return this.a.charCodeAt(b)}}
A.mH.prototype={
$0(){return A.n0(null,t.H)},
$S:2}
A.jo.prototype={}
A.p.prototype={}
A.a7.prototype={
gt(a){var s=this
return new A.cO(s,s.gk(s),A.D(s).h("cO<a7.E>"))},
gv(a){return this.gk(this)===0},
bd(a,b){var s,r,q,p=this,o=p.gk(p)
if(b.length!==0){if(o===0)return""
s=A.y(p.M(0,0))
if(o!==p.gk(p))throw A.a(A.a5(p))
for(r=s,q=1;q<o;++q){r=r+b+A.y(p.M(0,q))
if(o!==p.gk(p))throw A.a(A.a5(p))}return r.charCodeAt(0)==0?r:r}else{for(q=0,r="";q<o;++q){r+=A.y(p.M(0,q))
if(o!==p.gk(p))throw A.a(A.a5(p))}return r.charCodeAt(0)==0?r:r}},
iH(a){return this.bd(0,"")},
aR(a,b,c){return new A.aa(this,b,A.D(this).h("@<a7.E>").X(c).h("aa<1,2>"))},
ad(a,b){return A.e3(this,b,null,A.D(this).h("a7.E"))}}
A.cc.prototype={
fw(a,b,c,d){var s,r=this.b
A.ap(r,"start")
s=this.c
if(s!=null){A.ap(s,"end")
if(r>s)throw A.a(A.S(r,0,s,"start",null))}},
gfU(){var s=J.aw(this.a),r=this.c
if(r==null||r>s)return s
return r},
ghK(){var s=J.aw(this.a),r=this.b
if(r>s)return s
return r},
gk(a){var s,r=J.aw(this.a),q=this.b
if(q>=r)return 0
s=this.c
if(s==null||s>=r)return r-q
return s-q},
M(a,b){var s=this,r=s.ghK()+b
if(b<0||r>=s.gfU())throw A.a(A.fh(b,s.gk(0),s,null,"index"))
return J.hM(s.a,r)},
ad(a,b){var s,r,q=this
A.ap(b,"count")
s=q.b+b
r=q.c
if(r!=null&&s>=r)return new A.bU(q.$ti.h("bU<1>"))
return A.e3(q.a,s,r,q.$ti.c)},
bj(a,b){var s,r,q,p=this,o=p.b,n=p.a,m=J.au(n),l=m.gk(n),k=p.c
if(k!=null&&k<l)l=k
s=l-o
if(s<=0){n=J.oq(0,p.$ti.c)
return n}r=A.an(s,m.M(n,o),!1,p.$ti.c)
for(q=1;q<s;++q){r[q]=m.M(n,o+q)
if(m.gk(n)<l)throw A.a(A.a5(p))}return r}}
A.cO.prototype={
gm(){var s=this.d
return s==null?this.$ti.c.a(s):s},
l(){var s,r=this,q=r.a,p=J.au(q),o=p.gk(q)
if(r.b!==o)throw A.a(A.a5(q))
s=r.c
if(s>=o){r.d=null
return!1}r.d=p.M(q,s);++r.c
return!0}}
A.ba.prototype={
gt(a){return new A.fy(J.ae(this.a),this.b,A.D(this).h("fy<1,2>"))},
gk(a){return J.aw(this.a)},
gv(a){return J.mU(this.a)},
M(a,b){return this.b.$1(J.hM(this.a,b))}}
A.bT.prototype={$ip:1}
A.fy.prototype={
l(){var s=this,r=s.b
if(r.l()){s.a=s.c.$1(r.gm())
return!0}s.a=null
return!1},
gm(){var s=this.a
return s==null?this.$ti.y[1].a(s):s}}
A.aa.prototype={
gk(a){return J.aw(this.a)},
M(a,b){return this.b.$1(J.hM(this.a,b))}}
A.e8.prototype={
gt(a){return new A.e9(J.ae(this.a),this.b)},
aR(a,b,c){return new A.ba(this,b,this.$ti.h("@<1>").X(c).h("ba<1,2>"))}}
A.e9.prototype={
l(){var s,r
for(s=this.a,r=this.b;s.l();)if(r.$1(s.gm()))return!0
return!1},
gm(){return this.a.gm()}}
A.bc.prototype={
ad(a,b){A.hO(b,"count")
A.ap(b,"count")
return new A.bc(this.a,this.b+b,A.D(this).h("bc<1>"))},
gt(a){var s=this.a
return new A.fV(s.gt(s),this.b)}}
A.cH.prototype={
gk(a){var s=this.a,r=s.gk(s)-this.b
if(r>=0)return r
return 0},
ad(a,b){A.hO(b,"count")
A.ap(b,"count")
return new A.cH(this.a,this.b+b,this.$ti)},
$ip:1}
A.fV.prototype={
l(){var s,r
for(s=this.a,r=0;r<this.b;++r)s.l()
this.b=0
return s.l()},
gm(){return this.a.gm()}}
A.bU.prototype={
gt(a){return B.aG},
gv(a){return!0},
gk(a){return 0},
M(a,b){throw A.a(A.S(b,0,0,"index",null))},
aR(a,b,c){return new A.bU(c.h("bU<0>"))},
ad(a,b){A.ap(b,"count")
return this}}
A.fd.prototype={
l(){return!1},
gm(){throw A.a(A.fm())}}
A.ea.prototype={
gt(a){return new A.h9(J.ae(this.a),this.$ti.h("h9<1>"))}}
A.h9.prototype={
l(){var s,r
for(s=this.a,r=this.$ti.c;s.l();)if(r.b(s.gm()))return!0
return!1},
gm(){return this.$ti.c.a(this.a.gm())}}
A.dG.prototype={}
A.h0.prototype={
p(a,b,c){throw A.a(A.Y("Cannot modify an unmodifiable list"))},
H(a,b,c,d,e){throw A.a(A.Y("Cannot modify an unmodifiable list"))},
a8(a,b,c,d){return this.H(0,b,c,d,0)}}
A.d0.prototype={}
A.dX.prototype={
gk(a){return J.aw(this.a)},
M(a,b){var s=this.a,r=J.au(s)
return r.M(s,r.gk(s)-1-b)}}
A.eL.prototype={}
A.aB.prototype={$r:"+(1,2)",$s:1}
A.ev.prototype={$r:"+basicSupport,supportsReadWriteUnsafe(1,2)",$s:2}
A.ew.prototype={$r:"+controller,sync(1,2)",$s:3}
A.cn.prototype={$r:"+file,outFlags(1,2)",$s:4}
A.dz.prototype={
gv(a){return this.gk(this)===0},
i(a){return A.n7(this)},
gbF(){return new A.dg(this.ig(),A.D(this).h("dg<ao<1,2>>"))},
ig(){var s=this
return function(){var r=0,q=1,p=[],o,n,m
return function $async$gbF(a,b,c){if(b===1){p.push(c)
r=q}for(;;)switch(r){case 0:o=s.ga_(),o=o.gt(o),n=A.D(s).h("ao<1,2>")
case 2:if(!o.l()){r=3
break}m=o.gm()
r=4
return a.b=new A.ao(m,s.j(0,m),n),1
case 4:r=2
break
case 3:return 0
case 1:return a.c=p.at(-1),3}}}},
$iaf:1}
A.dA.prototype={
gk(a){return this.b.length},
gef(){var s=this.$keys
if(s==null){s=Object.keys(this.a)
this.$keys=s}return s},
N(a){if(typeof a!="string")return!1
if("__proto__"===a)return!1
return this.a.hasOwnProperty(a)},
j(a,b){if(!this.N(b))return null
return this.b[this.a[b]]},
Z(a,b){var s,r,q=this.gef(),p=this.b
for(s=q.length,r=0;r<s;++r)b.$2(q[r],p[r])},
ga_(){return new A.el(this.gef(),this.$ti.h("el<1>"))}}
A.el.prototype={
gk(a){return this.a.length},
gv(a){return 0===this.a.length},
gao(a){return 0!==this.a.length},
gt(a){var s=this.a
return new A.hs(s,s.length,this.$ti.h("hs<1>"))}}
A.hs.prototype={
gm(){var s=this.d
return s==null?this.$ti.c.a(s):s},
l(){var s=this,r=s.c
if(r>=s.b){s.d=null
return!1}s.d=s.a[r]
s.c=r+1
return!0}}
A.dY.prototype={}
A.jP.prototype={
af(a){var s,r,q=this,p=new RegExp(q.a).exec(a)
if(p==null)return null
s=Object.create(null)
r=q.b
if(r!==-1)s.arguments=p[r+1]
r=q.c
if(r!==-1)s.argumentsExpr=p[r+1]
r=q.d
if(r!==-1)s.expr=p[r+1]
r=q.e
if(r!==-1)s.method=p[r+1]
r=q.f
if(r!==-1)s.receiver=p[r+1]
return s}}
A.dU.prototype={
i(a){return"Null check operator used on a null value"}}
A.fs.prototype={
i(a){var s,r=this,q="NoSuchMethodError: method not found: '",p=r.b
if(p==null)return"NoSuchMethodError: "+r.a
s=r.c
if(s==null)return q+p+"' ("+r.a+")"
return q+p+"' on '"+s+"' ("+r.a+")"}}
A.h_.prototype={
i(a){var s=this.a
return s.length===0?"Error":"Error: "+s}}
A.fI.prototype={
i(a){return"Throw of null ('"+(this.a===null?"null":"undefined")+"' from JavaScript)"},
$ia6:1}
A.dE.prototype={}
A.ey.prototype={
i(a){var s,r=this.b
if(r!=null)return r
r=this.a
s=r!==null&&typeof r==="object"?r.stack:null
return this.b=s==null?"":s},
$ia0:1}
A.bQ.prototype={
i(a){var s=this.constructor,r=s==null?null:s.name
return"Closure '"+A.qj(r==null?"unknown":r)+"'"},
gjh(){return this},
$C:"$1",
$R:1,
$D:null}
A.i_.prototype={$C:"$0",$R:0}
A.i0.prototype={$C:"$2",$R:2}
A.jF.prototype={}
A.jy.prototype={
i(a){var s=this.$static_name
if(s==null)return"Closure of unknown static method"
return"Closure '"+A.qj(s)+"'"}}
A.dw.prototype={
a3(a,b){if(b==null)return!1
if(this===b)return!0
if(!(b instanceof A.dw))return!1
return this.$_target===b.$_target&&this.a===b.a},
gF(a){return(A.mI(this.a)^A.dW(this.$_target))>>>0},
i(a){return"Closure '"+this.$_name+"' of "+("Instance of '"+A.fM(this.a)+"'")}}
A.fR.prototype={
i(a){return"RuntimeError: "+this.a}}
A.bZ.prototype={
gk(a){return this.a},
gv(a){return this.a===0},
ga_(){return new A.b8(this,A.D(this).h("b8<1>"))},
gbF(){return new A.dN(this,A.D(this).h("dN<1,2>"))},
N(a){var s,r
if(typeof a=="string"){s=this.b
if(s==null)return!1
return s[a]!=null}else if(typeof a=="number"&&(a&0x3fffffff)===a){r=this.c
if(r==null)return!1
return r[a]!=null}else return this.iD(a)},
iD(a){var s=this.d
if(s==null)return!1
return this.cp(s[this.co(a)],a)>=0},
am(a,b){b.Z(0,new A.iZ(this))},
j(a,b){var s,r,q,p,o=null
if(typeof b=="string"){s=this.b
if(s==null)return o
r=s[b]
q=r==null?o:r.b
return q}else if(typeof b=="number"&&(b&0x3fffffff)===b){p=this.c
if(p==null)return o
r=p[b]
q=r==null?o:r.b
return q}else return this.iE(b)},
iE(a){var s,r,q=this.d
if(q==null)return null
s=q[this.co(a)]
r=this.cp(s,a)
if(r<0)return null
return s[r].b},
p(a,b,c){var s,r,q,p,o,n,m=this
if(typeof b=="string"){s=m.b
m.dW(s==null?m.b=m.d8():s,b,c)}else if(typeof b=="number"&&(b&0x3fffffff)===b){r=m.c
m.dW(r==null?m.c=m.d8():r,b,c)}else{q=m.d
if(q==null)q=m.d=m.d8()
p=m.co(b)
o=q[p]
if(o==null)q[p]=[m.cT(b,c)]
else{n=m.cp(o,b)
if(n>=0)o[n].b=c
else o.push(m.cT(b,c))}}},
eT(a,b){var s,r,q=this
if(q.N(a)){s=q.j(0,a)
return s==null?A.D(q).y[1].a(s):s}r=b.$0()
q.p(0,a,r)
return r},
u(a,b){var s=this
if(typeof b=="string")return s.dX(s.b,b)
else if(typeof b=="number"&&(b&0x3fffffff)===b)return s.dX(s.c,b)
else return s.iF(b)},
iF(a){var s,r,q,p,o=this,n=o.d
if(n==null)return null
s=o.co(a)
r=n[s]
q=o.cp(r,a)
if(q<0)return null
p=r.splice(q,1)[0]
o.dY(p)
if(r.length===0)delete n[s]
return p.b},
aw(a){var s=this
if(s.a>0){s.b=s.c=s.d=s.e=s.f=null
s.a=0
s.cS()}},
Z(a,b){var s=this,r=s.e,q=s.r
while(r!=null){b.$2(r.a,r.b)
if(q!==s.r)throw A.a(A.a5(s))
r=r.c}},
dW(a,b,c){var s=a[b]
if(s==null)a[b]=this.cT(b,c)
else s.b=c},
dX(a,b){var s
if(a==null)return null
s=a[b]
if(s==null)return null
this.dY(s)
delete a[b]
return s.b},
cS(){this.r=this.r+1&1073741823},
cT(a,b){var s,r=this,q=new A.j0(a,b)
if(r.e==null)r.e=r.f=q
else{s=r.f
s.toString
q.d=s
r.f=s.c=q}++r.a
r.cS()
return q},
dY(a){var s=this,r=a.d,q=a.c
if(r==null)s.e=q
else r.c=q
if(q==null)s.f=r
else q.d=r;--s.a
s.cS()},
co(a){return J.av(a)&1073741823},
cp(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.a_(a[r].a,b))return r
return-1},
i(a){return A.n7(this)},
d8(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s}}
A.iZ.prototype={
$2(a,b){this.a.p(0,a,b)},
$S(){return A.D(this.a).h("~(1,2)")}}
A.j0.prototype={}
A.b8.prototype={
gk(a){return this.a.a},
gv(a){return this.a.a===0},
gt(a){var s=this.a
return new A.fx(s,s.r,s.e)},
a5(a,b){return this.a.N(b)}}
A.fx.prototype={
gm(){return this.d},
l(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.a(A.a5(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=s.a
r.c=s.c
return!0}}}
A.cM.prototype={
gm(){return this.d},
l(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.a(A.a5(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=s.b
r.c=s.c
return!0}}}
A.dN.prototype={
gk(a){return this.a.a},
gv(a){return this.a.a===0},
gt(a){var s=this.a
return new A.fw(s,s.r,s.e,this.$ti.h("fw<1,2>"))}}
A.fw.prototype={
gm(){var s=this.d
s.toString
return s},
l(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.a(A.a5(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=new A.ao(s.a,s.b,r.$ti.h("ao<1,2>"))
r.c=s.c
return!0}}}
A.mB.prototype={
$1(a){return this.a(a)},
$S:33}
A.mC.prototype={
$2(a,b){return this.a(a,b)},
$S:35}
A.mD.prototype={
$1(a){return this.a(a)},
$S:85}
A.eu.prototype={
i(a){return this.ev(!1)},
ev(a){var s,r,q,p,o,n=this.fX(),m=this.ed(),l=(a?"Record ":"")+"("
for(s=n.length,r="",q=0;q<s;++q,r=", "){l+=r
p=n[q]
if(typeof p=="string")l=l+p+": "
o=m[q]
l=a?l+A.oI(o):l+A.y(o)}l+=")"
return l.charCodeAt(0)==0?l:l},
fX(){var s,r=this.$s
while($.lV.length<=r)$.lV.push(null)
s=$.lV[r]
if(s==null){s=this.fM()
$.lV[r]=s}return s},
fM(){var s,r,q,p=this.$r,o=p.indexOf("("),n=p.substring(1,o),m=p.substring(o),l=m==="()"?0:m.replace(/[^,]/g,"").length+1,k=t.K,j=J.op(l,k)
for(s=0;s<l;++s)j[s]=s
if(n!==""){r=n.split(",")
s=r.length
for(q=l;s>0;){--q;--s
j[q]=r[s]}}return A.j1(j,k)}}
A.hw.prototype={
ed(){return[this.a,this.b]},
a3(a,b){if(b==null)return!1
return b instanceof A.hw&&this.$s===b.$s&&J.a_(this.a,b.a)&&J.a_(this.b,b.b)},
gF(a){return A.n9(this.$s,this.a,this.b,B.k)}}
A.fr.prototype={
i(a){return"RegExp/"+this.a+"/"+this.b.flags},
ghe(){var s=this,r=s.c
if(r!=null)return r
r=s.b
return s.c=A.or(s.a,r.multiline,!r.ignoreCase,r.unicode,r.dotAll,"g")},
ij(a){var s=this.b.exec(a)
if(s==null)return null
return new A.en(s)},
eA(a,b){return new A.ha(this,b,0)},
fV(a,b){var s,r=this.ghe()
r.lastIndex=b
s=r.exec(a)
if(s==null)return null
return new A.en(s)}}
A.en.prototype={$idQ:1,$ifO:1}
A.ha.prototype={
gt(a){return new A.ki(this.a,this.b,this.c)}}
A.ki.prototype={
gm(){var s=this.d
return s==null?t.cz.a(s):s},
l(){var s,r,q,p,o,n,m=this,l=m.b
if(l==null)return!1
s=m.c
r=l.length
if(s<=r){q=m.a
p=q.fV(l,s)
if(p!=null){m.d=p
s=p.b
o=s.index
n=o+s[0].length
if(o===n){s=!1
if(q.b.unicode){q=m.c
o=q+1
if(o<r){r=l.charCodeAt(q)
if(r>=55296&&r<=56319){s=l.charCodeAt(o)
s=s>=56320&&s<=57343}}}n=(s?n+1:n)+1}m.c=n
return!0}}m.b=m.d=null
return!1}}
A.fY.prototype={$idQ:1}
A.hD.prototype={
gt(a){return new A.m4(this.a,this.b,this.c)}}
A.m4.prototype={
l(){var s,r,q=this,p=q.c,o=q.b,n=o.length,m=q.a,l=m.length
if(p+n>l){q.d=null
return!1}s=m.indexOf(o,p)
if(s<0){q.c=l+1
q.d=null
return!1}r=s+n
q.d=new A.fY(s,o)
q.c=r===q.c?r+1:r
return!0},
gm(){var s=this.d
s.toString
return s}}
A.he.prototype={
ej(){var s=this.b
if(s===this)throw A.a(new A.c_("Local '"+this.a+"' has not been initialized."))
return s},
a9(){var s=this.b
if(s===this)throw A.a(A.ou(this.a))
return s}}
A.cP.prototype={
gS(a){return B.bf},
eC(a,b,c){A.eM(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
i5(a,b,c){var s
A.eM(a,b,c)
s=new DataView(a,b)
return s},
eB(a){return this.i5(a,0,null)},
$iF:1,
$idx:1}
A.c1.prototype={$ic1:1}
A.dR.prototype={
gaa(a){if(((a.$flags|0)&2)!==0)return new A.hH(a.buffer)
else return a.buffer},
hb(a,b,c,d){var s=A.S(b,0,c,d,null)
throw A.a(s)},
e4(a,b,c,d){if(b>>>0!==b||b>c)this.hb(a,b,c,d)}}
A.hH.prototype={
eC(a,b,c){var s=A.aF(this.a,b,c)
s.$flags=3
return s},
eB(a){var s=A.ow(this.a,0,null)
s.$flags=3
return s},
$idx:1}
A.c2.prototype={
gS(a){return B.bg},
$iF:1,
$ic2:1,
$imV:1}
A.cR.prototype={
gk(a){return a.length},
em(a,b,c,d,e){var s,r,q=a.length
this.e4(a,b,q,"start")
this.e4(a,c,q,"end")
if(b>c)throw A.a(A.S(b,0,c,null,null))
s=c-b
if(e<0)throw A.a(A.M(e,null))
r=d.length
if(r-e<s)throw A.a(A.L("Not enough elements"))
if(e!==0||r!==s)d=d.subarray(e,e+s)
a.set(d,b)},
$iay:1}
A.bx.prototype={
j(a,b){A.bi(b,a,a.length)
return a[b]},
p(a,b,c){a.$flags&2&&A.v(a)
A.bi(b,a,a.length)
a[b]=c},
H(a,b,c,d,e){a.$flags&2&&A.v(a,5)
if(t.d4.b(d)){this.em(a,b,c,d,e)
return}this.dV(a,b,c,d,e)},
a8(a,b,c,d){return this.H(a,b,c,d,0)},
$ip:1,
$id:1,
$iu:1}
A.aA.prototype={
p(a,b,c){a.$flags&2&&A.v(a)
A.bi(b,a,a.length)
a[b]=c},
H(a,b,c,d,e){a.$flags&2&&A.v(a,5)
if(t.eB.b(d)){this.em(a,b,c,d,e)
return}this.dV(a,b,c,d,e)},
a8(a,b,c,d){return this.H(a,b,c,d,0)},
$ip:1,
$id:1,
$iu:1}
A.fA.prototype={
gS(a){return B.bh},
$iF:1,
$iiF:1}
A.fB.prototype={
gS(a){return B.bi},
$iF:1,
$iiG:1}
A.fC.prototype={
gS(a){return B.bj},
j(a,b){A.bi(b,a,a.length)
return a[b]},
$iF:1,
$iiT:1}
A.cQ.prototype={
gS(a){return B.bk},
j(a,b){A.bi(b,a,a.length)
return a[b]},
$iF:1,
$icQ:1,
$iiU:1}
A.fD.prototype={
gS(a){return B.bl},
j(a,b){A.bi(b,a,a.length)
return a[b]},
$iF:1,
$iiV:1}
A.fE.prototype={
gS(a){return B.bn},
j(a,b){A.bi(b,a,a.length)
return a[b]},
$iF:1,
$ijR:1}
A.fF.prototype={
gS(a){return B.bo},
j(a,b){A.bi(b,a,a.length)
return a[b]},
$iF:1,
$ijS:1}
A.dS.prototype={
gS(a){return B.bp},
gk(a){return a.length},
j(a,b){A.bi(b,a,a.length)
return a[b]},
$iF:1,
$ijT:1}
A.c3.prototype={
gS(a){return B.bq},
gk(a){return a.length},
j(a,b){A.bi(b,a,a.length)
return a[b]},
cR(a,b,c){return new Uint8Array(a.subarray(b,A.ul(b,c,a.length)))},
$iF:1,
$ic3:1,
$icd:1}
A.ep.prototype={}
A.eq.prototype={}
A.er.prototype={}
A.es.prototype={}
A.aP.prototype={
h(a){return A.eG(v.typeUniverse,this,a)},
X(a){return A.pr(v.typeUniverse,this,a)}}
A.hk.prototype={}
A.m7.prototype={
i(a){return A.aC(this.a,null)}}
A.hh.prototype={
i(a){return this.a}}
A.eC.prototype={$ibd:1}
A.kk.prototype={
$1(a){var s=this.a,r=s.a
s.a=null
r.$0()},
$S:11}
A.kj.prototype={
$1(a){var s,r
this.a.a=a
s=this.b
r=this.c
s.firstChild?s.removeChild(r):s.appendChild(r)},
$S:78}
A.kl.prototype={
$0(){this.a.$0()},
$S:4}
A.km.prototype={
$0(){this.a.$0()},
$S:4}
A.m5.prototype={
fC(a,b){if(self.setTimeout!=null)self.setTimeout(A.cz(new A.m6(this,b),0),a)
else throw A.a(A.Y("`setTimeout()` not found."))}}
A.m6.prototype={
$0(){this.b.$0()},
$S:0}
A.eb.prototype={
O(a){var s,r=this
if(a==null)a=r.$ti.c.a(a)
if(!r.b)r.a.br(a)
else{s=r.a
if(r.$ti.h("K<1>").b(a))s.e3(a)
else s.bs(a)}},
aO(a,b){var s
if(b==null)b=A.du(a)
s=this.a
if(this.b)s.Y(new A.T(a,b))
else s.aH(new A.T(a,b))},
a4(a){return this.aO(a,null)},
$idy:1}
A.mf.prototype={
$1(a){return this.a.$2(0,a)},
$S:6}
A.mg.prototype={
$2(a,b){this.a.$2(1,new A.dE(a,b))},
$S:84}
A.mr.prototype={
$2(a,b){this.a(a,b)},
$S:51}
A.hF.prototype={
gm(){return this.b},
hC(a,b){var s,r,q
a=a
b=b
s=this.a
for(;;)try{r=s(this,a,b)
return r}catch(q){b=q
a=1}},
l(){var s,r,q,p,o=this,n=null,m=0
for(;;){s=o.d
if(s!=null)try{if(s.l()){o.b=s.gm()
return!0}else o.d=null}catch(r){n=r
m=1
o.d=null}q=o.hC(m,n)
if(1===q)return!0
if(0===q){o.b=null
p=o.e
if(p==null||p.length===0){o.a=A.pm
return!1}o.a=p.pop()
m=0
n=null
continue}if(2===q){m=0
n=null
continue}if(3===q){n=o.c
o.c=null
p=o.e
if(p==null||p.length===0){o.b=null
o.a=A.pm
throw n
return!1}o.a=p.pop()
m=1
continue}throw A.a(A.L("sync*"))}return!1},
ji(a){var s,r,q=this
if(a instanceof A.dg){s=a.a()
r=q.e
if(r==null)r=q.e=[]
r.push(q.a)
q.a=s
return 2}else{q.d=J.ae(a)
return 2}}}
A.dg.prototype={
gt(a){return new A.hF(this.a())}}
A.T.prototype={
i(a){return A.y(this.a)},
$iG:1,
gb_(){return this.b}}
A.iM.prototype={
$0(){var s,r,q,p,o,n,m=null
try{m=this.a.$0()}catch(q){s=A.W(q)
r=A.al(q)
p=s
o=r
n=A.eO(p,o)
p=new A.T(p,o)
this.b.Y(p)
return}this.b.aJ(m)},
$S:0}
A.iL.prototype={
$0(){this.c.a(null)
this.b.aJ(null)},
$S:0}
A.iO.prototype={
$2(a,b){var s=this,r=s.a,q=--r.b
if(r.a!=null){r.a=null
r.d=a
r.c=b
if(q===0||s.c)s.d.Y(new A.T(a,b))}else if(q===0&&!s.c){q=r.d
q.toString
r=r.c
r.toString
s.d.Y(new A.T(q,r))}},
$S:7}
A.iN.prototype={
$1(a){var s,r,q,p,o,n,m=this,l=m.a,k=--l.b,j=l.a
if(j!=null){J.nZ(j,m.b,a)
if(J.a_(k,0)){l=m.d
s=A.n([],l.h("t<0>"))
for(q=j,p=q.length,o=0;o<q.length;q.length===p||(0,A.R)(q),++o){r=q[o]
n=r
if(n==null)n=l.a(n)
J.o_(s,n)}m.c.bs(s)}}else if(J.a_(k,0)&&!m.f){s=l.d
s.toString
l=l.c
l.toString
m.c.Y(new A.T(s,l))}},
$S(){return this.d.h("B(0)")}}
A.iH.prototype={
$2(a,b){if(!this.a.b(a))throw A.a(a)
return this.c.$2(a,b)},
$S(){return this.d.h("0/(l,a0)")}}
A.d4.prototype={
aO(a,b){if((this.a.a&30)!==0)throw A.a(A.L("Future already completed"))
this.Y(A.pP(a,b))},
a4(a){return this.aO(a,null)},
$idy:1}
A.b2.prototype={
O(a){var s=this.a
if((s.a&30)!==0)throw A.a(A.L("Future already completed"))
s.br(a)},
aN(){return this.O(null)},
Y(a){this.a.aH(a)}}
A.H.prototype={
O(a){var s=this.a
if((s.a&30)!==0)throw A.a(A.L("Future already completed"))
s.aJ(a)},
aN(){return this.O(null)},
Y(a){this.a.Y(a)}}
A.b3.prototype={
iO(a){if((this.c&15)!==6)return!0
return this.b.b.dM(this.d,a.a)},
is(a){var s,r=this.e,q=null,p=a.a,o=this.b.b
if(t.V.b(r))q=o.j2(r,p,a.b)
else q=o.dM(r,p)
try{p=q
return p}catch(s){if(t.eK.b(A.W(s))){if((this.c&1)!==0)throw A.a(A.M("The error handler of Future.then must return a value of the returned future's type","onError"))
throw A.a(A.M("The error handler of Future.catchError must return a value of the future's type","onError"))}else throw s}}}
A.m.prototype={
bi(a,b,c){var s,r,q=$.q
if(q===B.e){if(b!=null&&!t.V.b(b)&&!t.bI.b(b))throw A.a(A.aD(b,"onError",u.c))}else if(b!=null)b=A.uQ(b,q)
s=new A.m(q,c.h("m<0>"))
r=b==null?1:3
this.bq(new A.b3(s,r,a,b,this.$ti.h("@<1>").X(c).h("b3<1,2>")))
return s},
dO(a,b){return this.bi(a,null,b)},
es(a,b,c){var s=new A.m($.q,c.h("m<0>"))
this.bq(new A.b3(s,19,a,b,this.$ti.h("@<1>").X(c).h("b3<1,2>")))
return s},
W(a){var s=this.$ti,r=new A.m($.q,s)
this.bq(new A.b3(r,8,a,null,s.h("b3<1,1>")))
return r},
hG(a){this.a=this.a&1|16
this.c=a},
bV(a){this.a=a.a&30|this.a&1
this.c=a.c},
bq(a){var s=this,r=s.a
if(r<=3){a.a=s.c
s.c=a}else{if((r&4)!==0){r=s.c
if((r.a&24)===0){r.bq(a)
return}s.bV(r)}A.dm(null,null,s.b,new A.kQ(s,a))}},
ei(a){var s,r,q,p,o,n=this,m={}
m.a=a
if(a==null)return
s=n.a
if(s<=3){r=n.c
n.c=a
if(r!=null){q=a.a
for(p=a;q!=null;p=q,q=o)o=q.a
p.a=r}}else{if((s&4)!==0){s=n.c
if((s.a&24)===0){s.ei(a)
return}n.bV(s)}m.a=n.bZ(a)
A.dm(null,null,n.b,new A.kV(m,n))}},
bv(){var s=this.c
this.c=null
return this.bZ(s)},
bZ(a){var s,r,q
for(s=a,r=null;s!=null;r=s,s=q){q=s.a
s.a=r}return r},
aJ(a){var s,r=this
if(r.$ti.h("K<1>").b(a))A.kT(a,r,!0)
else{s=r.bv()
r.a=8
r.c=a
A.ck(r,s)}},
bs(a){var s=this,r=s.bv()
s.a=8
s.c=a
A.ck(s,r)},
fL(a){var s,r,q=this
if((a.a&16)!==0){s=q.b===a.b
s=!(s||s)}else s=!1
if(s)return
r=q.bv()
q.bV(a)
A.ck(q,r)},
Y(a){var s=this.bv()
this.hG(a)
A.ck(this,s)},
fK(a,b){this.Y(new A.T(a,b))},
br(a){if(this.$ti.h("K<1>").b(a)){this.e3(a)
return}this.e1(a)},
e1(a){this.a^=2
A.dm(null,null,this.b,new A.kS(this,a))},
e3(a){A.kT(a,this,!1)
return},
aH(a){this.a^=2
A.dm(null,null,this.b,new A.kR(this,a))},
$iK:1}
A.kQ.prototype={
$0(){A.ck(this.a,this.b)},
$S:0}
A.kV.prototype={
$0(){A.ck(this.b,this.a.a)},
$S:0}
A.kU.prototype={
$0(){A.kT(this.a.a,this.b,!0)},
$S:0}
A.kS.prototype={
$0(){this.a.bs(this.b)},
$S:0}
A.kR.prototype={
$0(){this.a.Y(this.b)},
$S:0}
A.kY.prototype={
$0(){var s,r,q,p,o,n,m,l,k=this,j=null
try{q=k.a.a
j=q.b.b.f0(q.d)}catch(p){s=A.W(p)
r=A.al(p)
if(k.c&&k.b.a.c.a===s){q=k.a
q.c=k.b.a.c}else{q=s
o=r
if(o==null)o=A.du(q)
n=k.a
n.c=new A.T(q,o)
q=n}q.b=!0
return}if(j instanceof A.m&&(j.a&24)!==0){if((j.a&16)!==0){q=k.a
q.c=j.c
q.b=!0}return}if(j instanceof A.m){m=k.b.a
l=new A.m(m.b,m.$ti)
j.bi(new A.kZ(l,m),new A.l_(l),t.H)
q=k.a
q.c=l
q.b=!1}},
$S:0}
A.kZ.prototype={
$1(a){this.a.fL(this.b)},
$S:11}
A.l_.prototype={
$2(a,b){this.a.Y(new A.T(a,b))},
$S:12}
A.kX.prototype={
$0(){var s,r,q,p,o,n
try{q=this.a
p=q.a
q.c=p.b.b.dM(p.d,this.b)}catch(o){s=A.W(o)
r=A.al(o)
q=s
p=r
if(p==null)p=A.du(q)
n=this.a
n.c=new A.T(q,p)
n.b=!0}},
$S:0}
A.kW.prototype={
$0(){var s,r,q,p,o,n,m,l=this
try{s=l.a.a.c
p=l.b
if(p.a.iO(s)&&p.a.e!=null){p.c=p.a.is(s)
p.b=!1}}catch(o){r=A.W(o)
q=A.al(o)
p=l.a.a.c
if(p.a===r){n=l.b
n.c=p
p=n}else{p=r
n=q
if(n==null)n=A.du(p)
m=l.b
m.c=new A.T(p,n)
p=m}p.b=!0}},
$S:0}
A.hb.prototype={}
A.a1.prototype={
gk(a){var s={},r=new A.m($.q,t.fJ)
s.a=0
this.U(new A.jC(s,this),!0,new A.jD(s,r),r.ge6())
return r},
gaA(a){var s=new A.m($.q,A.D(this).h("m<a1.T>")),r=this.U(null,!0,new A.jA(s),s.ge6())
r.eQ(new A.jB(this,r,s))
return s}}
A.jC.prototype={
$1(a){++this.a.a},
$S(){return A.D(this.b).h("~(a1.T)")}}
A.jD.prototype={
$0(){this.b.aJ(this.a.a)},
$S:0}
A.jA.prototype={
$0(){var s,r=A.oR(),q=new A.b0("No element")
A.jd(q,r)
s=A.eO(q,r)
s=new A.T(q,r)
this.a.Y(s)},
$S:0}
A.jB.prototype={
$1(a){A.ui(this.b,this.c,a)},
$S(){return A.D(this.a).h("~(a1.T)")}}
A.co.prototype={
ghp(){if((this.b&8)===0)return this.a
return this.a.gbA()},
bt(){var s,r=this
if((r.b&8)===0){s=r.a
return s==null?r.a=new A.et():s}s=r.a.gbA()
return s},
gak(){var s=this.a
return(this.b&8)!==0?s.gbA():s},
aI(){if((this.b&4)!==0)return new A.b0("Cannot add event after closing")
return new A.b0("Cannot add event while adding a stream")},
ea(){var s=this.c
if(s==null)s=this.c=(this.b&2)!==0?$.dt():new A.m($.q,t.D)
return s},
E(a,b){var s=this,r=s.b
if(r>=4)throw A.a(s.aI())
if((r&1)!==0)s.aL(b)
else if((r&3)===0)s.bt().E(0,new A.bI(b))},
ez(a,b){var s,r,q=this
if(q.b>=4)throw A.a(q.aI())
s=A.pP(a,b)
a=s.a
b=s.b
r=q.b
if((r&1)!==0)q.bz(a,b)
else if((r&3)===0)q.bt().E(0,new A.eg(a,b))},
i0(a){return this.ez(a,null)},
q(){var s=this,r=s.b
if((r&4)!==0)return s.ea()
if(r>=4)throw A.a(s.aI())
r=s.b=r|4
if((r&1)!==0)s.by()
else if((r&3)===0)s.bt().E(0,B.r)
return s.ea()},
ep(a,b,c,d){var s,r,q,p,o,n,m,l,k,j=this
if((j.b&3)!==0)throw A.a(A.L("Stream has already been listened to."))
s=$.q
r=d?1:0
q=b!=null?32:0
p=A.nt(s,a)
o=A.pb(s,b)
n=c==null?A.v3():c
m=new A.d7(j,p,o,n,s,r|q,A.D(j).h("d7<1>"))
l=j.ghp()
if(((j.b|=1)&8)!==0){k=j.a
k.sbA(m)
k.aU()}else j.a=m
m.hH(l)
m.d4(new A.m0(j))
return m},
hv(a){var s,r,q,p,o,n,m,l=this,k=null
if((l.b&8)!==0)k=l.a.B()
l.a=null
l.b=l.b&4294967286|2
s=l.r
if(s!=null)if(k==null)try{r=s.$0()
if(r instanceof A.m)k=r}catch(o){q=A.W(o)
p=A.al(o)
n=new A.m($.q,t.D)
n.aH(new A.T(q,p))
k=n}else k=k.W(s)
m=new A.m_(l)
if(k!=null)k=k.W(m)
else m.$0()
return k}}
A.m0.prototype={
$0(){A.nI(this.a.d)},
$S:0}
A.m_.prototype={
$0(){var s=this.a.c
if(s!=null&&(s.a&30)===0)s.br(null)},
$S:0}
A.hG.prototype={
aL(a){this.gak().b3(a)},
bz(a,b){this.gak().bp(a,b)},
by(){this.gak().e5()}}
A.hc.prototype={
aL(a){this.gak().b2(new A.bI(a))},
bz(a,b){this.gak().b2(new A.eg(a,b))},
by(){this.gak().b2(B.r)}}
A.bF.prototype={}
A.dh.prototype={}
A.as.prototype={
gF(a){return(A.dW(this.a)^892482866)>>>0},
a3(a,b){if(b==null)return!1
if(this===b)return!0
return b instanceof A.as&&b.a===this.a}}
A.d7.prototype={
da(){return this.w.hv(this)},
b5(){var s=this.w
if((s.b&8)!==0)s.a.ct()
A.nI(s.e)},
b6(){var s=this.w
if((s.b&8)!==0)s.a.aU()
A.nI(s.f)}}
A.eA.prototype={}
A.bG.prototype={
hH(a){var s=this
if(a==null)return
s.r=a
if(a.c!=null){s.e=(s.e|128)>>>0
a.bR(s)}},
eQ(a){this.a=A.nt(this.d,a)},
cu(a){var s,r=this,q=r.e
if((q&8)!==0)return
r.e=(q+256|4)>>>0
if(a!=null)a.W(r.gdL())
if(q<256){s=r.r
if(s!=null)if(s.a===1)s.a=3}if((q&4)===0&&(r.e&64)===0)r.d4(r.gdc())},
ct(){return this.cu(null)},
aU(){var s=this,r=s.e
if((r&8)!==0)return
if(r>=256){r=s.e=r-256
if(r<256)if((r&128)!==0&&s.r.c!=null)s.r.bR(s)
else{r=(r&4294967291)>>>0
s.e=r
if((r&64)===0)s.d4(s.gdd())}}},
B(){var s=this,r=(s.e&4294967279)>>>0
s.e=r
if((r&8)===0)s.cV()
r=s.f
return r==null?$.dt():r},
cV(){var s,r=this,q=r.e=(r.e|8)>>>0
if((q&128)!==0){s=r.r
if(s.a===1)s.a=3}if((q&64)===0)r.r=null
r.f=r.da()},
b3(a){var s=this.e
if((s&8)!==0)return
if(s<64)this.aL(a)
else this.b2(new A.bI(a))},
bp(a,b){var s
if(t.C.b(a))A.jd(a,b)
s=this.e
if((s&8)!==0)return
if(s<64)this.bz(a,b)
else this.b2(new A.eg(a,b))},
e5(){var s=this,r=s.e
if((r&8)!==0)return
r=(r|2)>>>0
s.e=r
if(r<64)s.by()
else s.b2(B.r)},
b5(){},
b6(){},
da(){return null},
b2(a){var s,r=this,q=r.r
if(q==null)q=r.r=new A.et()
q.E(0,a)
s=r.e
if((s&128)===0){s=(s|128)>>>0
r.e=s
if(s<256)q.bR(r)}},
aL(a){var s=this,r=s.e
s.e=(r|64)>>>0
s.d.dN(s.a,a)
s.e=(s.e&4294967231)>>>0
s.cX((r&4)!==0)},
bz(a,b){var s,r=this,q=r.e,p=new A.kr(r,a,b)
if((q&1)!==0){r.e=(q|16)>>>0
r.cV()
s=r.f
if(s!=null&&s!==$.dt())s.W(p)
else p.$0()}else{p.$0()
r.cX((q&4)!==0)}},
by(){var s,r=this,q=new A.kq(r)
r.cV()
r.e=(r.e|16)>>>0
s=r.f
if(s!=null&&s!==$.dt())s.W(q)
else q.$0()},
d4(a){var s=this,r=s.e
s.e=(r|64)>>>0
a.$0()
s.e=(s.e&4294967231)>>>0
s.cX((r&4)!==0)},
cX(a){var s,r,q=this,p=q.e
if((p&128)!==0&&q.r.c==null){p=q.e=(p&4294967167)>>>0
s=!1
if((p&4)!==0)if(p<256){s=q.r
s=s==null?null:s.c==null
s=s!==!1}if(s){p=(p&4294967291)>>>0
q.e=p}}for(;;a=r){if((p&8)!==0){q.r=null
return}r=(p&4)!==0
if(a===r)break
q.e=(p^64)>>>0
if(r)q.b5()
else q.b6()
p=(q.e&4294967231)>>>0
q.e=p}if((p&128)!==0&&p<256)q.r.bR(q)},
$iaH:1}
A.kr.prototype={
$0(){var s,r,q=this.a,p=q.e
if((p&8)!==0&&(p&16)===0)return
q.e=(p|64)>>>0
s=q.b
p=this.b
r=q.d
if(t.da.b(s))r.j5(s,p,this.c)
else r.dN(s,p)
q.e=(q.e&4294967231)>>>0},
$S:0}
A.kq.prototype={
$0(){var s=this.a,r=s.e
if((r&16)===0)return
s.e=(r|74)>>>0
s.d.f1(s.c)
s.e=(s.e&4294967231)>>>0},
$S:0}
A.ez.prototype={
U(a,b,c,d){return this.a.ep(a,d,c,b===!0)},
be(a,b,c){return this.U(a,null,b,c)},
iK(a,b){return this.U(a,null,null,b)},
iJ(a,b){return this.U(a,null,b,null)}}
A.hg.prototype={
gaS(){return this.a},
saS(a){return this.a=a}}
A.bI.prototype={
dJ(a){a.aL(this.b)}}
A.eg.prototype={
dJ(a){a.bz(this.b,this.c)}}
A.kJ.prototype={
dJ(a){a.by()},
gaS(){return null},
saS(a){throw A.a(A.L("No events after a done."))}}
A.et.prototype={
bR(a){var s=this,r=s.a
if(r===1)return
if(r>=1){s.a=1
return}A.vS(new A.lU(s,a))
s.a=1},
E(a,b){var s=this,r=s.c
if(r==null)s.b=s.c=b
else{r.saS(b)
s.c=b}}}
A.lU.prototype={
$0(){var s,r,q=this.a,p=q.a
q.a=0
if(p===3)return
s=q.b
r=s.gaS()
q.b=r
if(r==null)q.c=null
s.dJ(this.b)},
$S:0}
A.cp.prototype={
gm(){if(this.c)return this.b
return null},
l(){var s,r=this,q=r.a
if(q!=null){if(r.c){s=new A.m($.q,t.k)
r.b=s
r.c=!1
q.aU()
return s}throw A.a(A.L("Already waiting for next."))}return r.ha()},
ha(){var s,r,q=this,p=q.b
if(p!=null){s=new A.m($.q,t.k)
q.b=s
r=p.U(q.ghg(),!0,q.ghi(),q.ghk())
if(q.b!=null)q.a=r
return s}return $.ql()},
B(){var s=this,r=s.a,q=s.b
s.b=null
if(r!=null){s.a=null
if(!s.c)q.br(!1)
else s.c=!1
return r.B()}return $.dt()},
hh(a){var s,r,q=this
if(q.a==null)return
s=q.b
q.b=a
q.c=!0
s.aJ(!0)
if(q.c){r=q.a
if(r!=null)r.ct()}},
hl(a,b){var s=this,r=s.a,q=s.b
s.b=s.a=null
if(r!=null)q.Y(new A.T(a,b))
else q.aH(new A.T(a,b))},
hj(){var s=this,r=s.a,q=s.b
s.b=s.a=null
if(r!=null)q.bs(!1)
else q.e1(!1)}}
A.bh.prototype={
U(a,b,c,d){var s=null,r=new A.eo(s,s,s,s,this.$ti.h("eo<1>"))
r.d=new A.lT(this,r)
return r.ep(a,d,c,b===!0)},
be(a,b,c){return this.U(a,null,b,c)},
aQ(a){return this.U(a,null,null,null)}}
A.lT.prototype={
$0(){this.a.b.$1(this.b)},
$S:0}
A.eo.prototype={
i3(a){var s=this.b
if(s>=4)throw A.a(this.aI())
if((s&1)!==0)this.gak().b3(a)},
$ic0:1}
A.mh.prototype={
$0(){return this.a.aJ(this.b)},
$S:0}
A.ei.prototype={
U(a,b,c,d){var s=$.q,r=b===!0?1:0,q=A.nt(s,a),p=A.pb(s,d)
s=new A.da(this,q,p,c,s,r|32,this.$ti.h("da<1,2>"))
s.x=this.a.be(s.gh1(),s.gh4(),s.gh6())
return s},
be(a,b,c){return this.U(a,null,b,c)}}
A.da.prototype={
b3(a){if((this.e&2)!==0)return
this.fq(a)},
bp(a,b){if((this.e&2)!==0)return
this.fs(a,b)},
b5(){var s=this.x
if(s!=null)s.ct()},
b6(){var s=this.x
if(s!=null)s.aU()},
da(){var s=this.x
if(s!=null){this.x=null
return s.B()}return null},
h2(a){this.w.h3(a,this)},
h7(a,b){this.bp(a,b)},
h5(){this.e5()}}
A.cl.prototype={
h3(a,b){var s,r,q,p,o,n=null
try{n=this.b.$1(a)}catch(q){s=A.W(q)
r=A.al(q)
p=s
o=r
A.eO(p,o)
b.bp(p,o)
return}b.b3(n)}}
A.me.prototype={}
A.lX.prototype={
f1(a){var s,r,q
try{if(B.e===$.q){a.$0()
return}A.pV(null,null,this,a)}catch(q){s=A.W(q)
r=A.al(q)
A.dl(s,r)}},
j7(a,b){var s,r,q
try{if(B.e===$.q){a.$1(b)
return}A.pX(null,null,this,a,b)}catch(q){s=A.W(q)
r=A.al(q)
A.dl(s,r)}},
dN(a,b){return this.j7(a,b,t.z)},
j4(a,b,c){var s,r,q
try{if(B.e===$.q){a.$2(b,c)
return}A.pW(null,null,this,a,b,c)}catch(q){s=A.W(q)
r=A.al(q)
A.dl(s,r)}},
j5(a,b,c){var s=t.z
return this.j4(a,b,c,s,s)},
dq(a){return new A.lY(this,a)},
eD(a,b){return new A.lZ(this,a,b)},
j1(a){if($.q===B.e)return a.$0()
return A.pV(null,null,this,a)},
f0(a){return this.j1(a,t.z)},
j6(a,b){if($.q===B.e)return a.$1(b)
return A.pX(null,null,this,a,b)},
dM(a,b){var s=t.z
return this.j6(a,b,s,s)},
j3(a,b,c){if($.q===B.e)return a.$2(b,c)
return A.pW(null,null,this,a,b,c)},
j2(a,b,c){var s=t.z
return this.j3(a,b,c,s,s,s)},
iY(a){return a},
cv(a){var s=t.z
return this.iY(a,s,s,s)}}
A.lY.prototype={
$0(){return this.a.f1(this.b)},
$S:0}
A.lZ.prototype={
$1(a){return this.a.dN(this.b,a)},
$S(){return this.c.h("~(0)")}}
A.mp.prototype={
$0(){A.rq(this.a,this.b)},
$S:0}
A.ej.prototype={
gk(a){return this.a},
gv(a){return this.a===0},
ga_(){return new A.ek(this,this.$ti.h("ek<1>"))},
N(a){var s,r
if(typeof a=="string"&&a!=="__proto__"){s=this.b
return s==null?!1:s[a]!=null}else if(typeof a=="number"&&(a&1073741823)===a){r=this.c
return r==null?!1:r[a]!=null}else return this.fP(a)},
fP(a){var s=this.d
if(s==null)return!1
return this.aK(this.ec(s,a),a)>=0},
j(a,b){var s,r,q
if(typeof b=="string"&&b!=="__proto__"){s=this.b
r=s==null?null:A.pf(s,b)
return r}else if(typeof b=="number"&&(b&1073741823)===b){q=this.c
r=q==null?null:A.pf(q,b)
return r}else return this.h0(b)},
h0(a){var s,r,q=this.d
if(q==null)return null
s=this.ec(q,a)
r=this.aK(s,a)
return r<0?null:s[r+1]},
p(a,b,c){var s,r,q,p,o,n,m=this
if(typeof b=="string"&&b!=="__proto__"){s=m.b
m.e0(s==null?m.b=A.nu():s,b,c)}else if(typeof b=="number"&&(b&1073741823)===b){r=m.c
m.e0(r==null?m.c=A.nu():r,b,c)}else{q=m.d
if(q==null)q=m.d=A.nu()
p=A.mI(b)&1073741823
o=q[p]
if(o==null){A.nv(q,p,[b,c]);++m.a
m.e=null}else{n=m.aK(o,b)
if(n>=0)o[n+1]=c
else{o.push(b,c);++m.a
m.e=null}}}},
Z(a,b){var s,r,q,p,o,n=this,m=n.e7()
for(s=m.length,r=n.$ti.y[1],q=0;q<s;++q){p=m[q]
o=n.j(0,p)
b.$2(p,o==null?r.a(o):o)
if(m!==n.e)throw A.a(A.a5(n))}},
e7(){var s,r,q,p,o,n,m,l,k,j,i=this,h=i.e
if(h!=null)return h
h=A.an(i.a,null,!1,t.z)
s=i.b
r=0
if(s!=null){q=Object.getOwnPropertyNames(s)
p=q.length
for(o=0;o<p;++o){h[r]=q[o];++r}}n=i.c
if(n!=null){q=Object.getOwnPropertyNames(n)
p=q.length
for(o=0;o<p;++o){h[r]=+q[o];++r}}m=i.d
if(m!=null){q=Object.getOwnPropertyNames(m)
p=q.length
for(o=0;o<p;++o){l=m[q[o]]
k=l.length
for(j=0;j<k;j+=2){h[r]=l[j];++r}}}return i.e=h},
e0(a,b,c){if(a[b]==null){++this.a
this.e=null}A.nv(a,b,c)},
ec(a,b){return a[A.mI(b)&1073741823]}}
A.db.prototype={
aK(a,b){var s,r,q
if(a==null)return-1
s=a.length
for(r=0;r<s;r+=2){q=a[r]
if(q==null?b==null:q===b)return r}return-1}}
A.ek.prototype={
gk(a){return this.a.a},
gv(a){return this.a.a===0},
gao(a){return this.a.a!==0},
gt(a){var s=this.a
return new A.hm(s,s.e7(),this.$ti.h("hm<1>"))},
a5(a,b){return this.a.N(b)}}
A.hm.prototype={
gm(){var s=this.d
return s==null?this.$ti.c.a(s):s},
l(){var s=this,r=s.b,q=s.c,p=s.a
if(r!==p.e)throw A.a(A.a5(p))
else if(q>=r.length){s.d=null
return!1}else{s.d=r[q]
s.c=q+1
return!0}}}
A.em.prototype={
gt(a){var s=this,r=new A.dc(s,s.r,s.$ti.h("dc<1>"))
r.c=s.e
return r},
gk(a){return this.a},
gv(a){return this.a===0},
gao(a){return this.a!==0},
a5(a,b){var s,r
if(b!=="__proto__"){s=this.b
if(s==null)return!1
return s[b]!=null}else{r=this.fO(b)
return r}},
fO(a){var s=this.d
if(s==null)return!1
return this.aK(s[B.a.gF(a)&1073741823],a)>=0},
E(a,b){var s,r,q=this
if(typeof b=="string"&&b!=="__proto__"){s=q.b
return q.e_(s==null?q.b=A.nw():s,b)}else if(typeof b=="number"&&(b&1073741823)===b){r=q.c
return q.e_(r==null?q.c=A.nw():r,b)}else return q.fD(b)},
fD(a){var s,r,q=this,p=q.d
if(p==null)p=q.d=A.nw()
s=J.av(a)&1073741823
r=p[s]
if(r==null)p[s]=[q.d9(a)]
else{if(q.aK(r,a)>=0)return!1
r.push(q.d9(a))}return!0},
u(a,b){var s=this
if(typeof b=="string"&&b!=="__proto__")return s.ek(s.b,b)
else if(typeof b=="number"&&(b&1073741823)===b)return s.ek(s.c,b)
else return s.dg(b)},
dg(a){var s,r,q,p,o=this.d
if(o==null)return!1
s=J.av(a)&1073741823
r=o[s]
q=this.aK(r,a)
if(q<0)return!1
p=r.splice(q,1)[0]
if(0===r.length)delete o[s]
this.ew(p)
return!0},
aw(a){var s=this
if(s.a>0){s.b=s.c=s.d=s.e=s.f=null
s.a=0
s.d7()}},
e_(a,b){if(a[b]!=null)return!1
a[b]=this.d9(b)
return!0},
ek(a,b){var s
if(a==null)return!1
s=a[b]
if(s==null)return!1
this.ew(s)
delete a[b]
return!0},
d7(){this.r=this.r+1&1073741823},
d9(a){var s,r=this,q=new A.lS(a)
if(r.e==null)r.e=r.f=q
else{s=r.f
s.toString
q.c=s
r.f=s.b=q}++r.a
r.d7()
return q},
ew(a){var s=this,r=a.c,q=a.b
if(r==null)s.e=q
else r.b=q
if(q==null)s.f=r
else q.c=r;--s.a
s.d7()},
aK(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.a_(a[r].a,b))return r
return-1}}
A.lS.prototype={}
A.dc.prototype={
gm(){var s=this.d
return s==null?this.$ti.c.a(s):s},
l(){var s=this,r=s.c,q=s.a
if(s.b!==q.r)throw A.a(A.a5(q))
else if(r==null){s.d=null
return!1}else{s.d=r.a
s.c=r.b
return!0}}}
A.dO.prototype={
u(a,b){if(b.a!==this)return!1
this.dj(b)
return!0},
gt(a){var s=this
return new A.ht(s,s.a,s.c,s.$ti.h("ht<1>"))},
gk(a){return this.b},
gaA(a){var s
if(this.b===0)throw A.a(A.L("No such element"))
s=this.c
s.toString
return s},
gap(a){var s
if(this.b===0)throw A.a(A.L("No such element"))
s=this.c.c
s.toString
return s},
gv(a){return this.b===0},
d5(a,b,c){var s,r,q=this
if(b.a!=null)throw A.a(A.L("LinkedListEntry is already in a LinkedList"));++q.a
b.a=q
s=q.b
if(s===0){b.b=b
q.c=b.c=b
q.b=s+1
return}r=a.c
r.toString
b.c=r
b.b=a
a.c=r.b=b
q.b=s+1},
dj(a){var s,r,q=this;++q.a
s=a.b
s.c=a.c
a.c.b=s
r=--q.b
a.a=a.b=a.c=null
if(r===0)q.c=null
else if(a===q.c)q.c=s}}
A.ht.prototype={
gm(){var s=this.c
return s==null?this.$ti.c.a(s):s},
l(){var s=this,r=s.a
if(s.b!==r.a)throw A.a(A.a5(s))
if(r.b!==0)r=s.e&&s.d===r.gaA(0)
else r=!0
if(r){s.c=null
return!1}s.e=!0
r=s.d
s.c=r
s.d=r.b
return!0}}
A.am.prototype={
gbM(){var s=this.a
if(s==null||this===s.gaA(0))return null
return this.c}}
A.x.prototype={
gt(a){return new A.cO(a,this.gk(a),A.bL(a).h("cO<x.E>"))},
M(a,b){return this.j(a,b)},
gv(a){return this.gk(a)===0},
gao(a){return!this.gv(a)},
aR(a,b,c){return new A.aa(a,b,A.bL(a).h("@<x.E>").X(c).h("aa<1,2>"))},
ad(a,b){return A.e3(a,b,null,A.bL(a).h("x.E"))},
f2(a,b){return A.e3(a,0,A.cx(b,"count",t.S),A.bL(a).h("x.E"))},
dt(a,b,c,d){var s
A.c6(b,c,this.gk(a))
for(s=b;s<c;++s)this.p(a,s,d)},
H(a,b,c,d,e){var s,r,q,p,o
A.c6(b,c,this.gk(a))
s=c-b
if(s===0)return
A.ap(e,"skipCount")
if(t.j.b(d)){r=e
q=d}else{q=J.hN(d,e).bj(0,!1)
r=0}p=J.au(q)
if(r+s>p.gk(q))throw A.a(A.on())
if(r<b)for(o=s-1;o>=0;--o)this.p(a,b+o,p.j(q,r+o))
else for(o=0;o<s;++o)this.p(a,b+o,p.j(q,r+o))},
a8(a,b,c,d){return this.H(a,b,c,d,0)},
aF(a,b,c){var s,r
if(t.j.b(c))this.a8(a,b,b+c.length,c)
else for(s=J.ae(c);s.l();b=r){r=b+1
this.p(a,b,s.gm())}},
i(a){return A.iX(a,"[","]")},
$ip:1,
$id:1,
$iu:1}
A.N.prototype={
Z(a,b){var s,r,q,p
for(s=J.ae(this.ga_()),r=A.D(this).h("N.V");s.l();){q=s.gm()
p=this.j(0,q)
b.$2(q,p==null?r.a(p):p)}},
gbF(){return J.o0(this.ga_(),new A.j2(this),A.D(this).h("ao<N.K,N.V>"))},
N(a){return J.qU(this.ga_(),a)},
gk(a){return J.aw(this.ga_())},
gv(a){return J.mU(this.ga_())},
i(a){return A.n7(this)},
$iaf:1}
A.j2.prototype={
$1(a){var s=this.a,r=s.j(0,a)
if(r==null)r=A.D(s).h("N.V").a(r)
return new A.ao(a,r,A.D(s).h("ao<N.K,N.V>"))},
$S(){return A.D(this.a).h("ao<N.K,N.V>(N.K)")}}
A.j3.prototype={
$2(a,b){var s,r=this.a
if(!r.a)this.b.a+=", "
r.a=!1
r=this.b
s=A.y(a)
r.a=(r.a+=s)+": "
s=A.y(b)
r.a+=s},
$S:26}
A.dP.prototype={
gt(a){var s=this
return new A.hu(s,s.c,s.d,s.b,s.$ti.h("hu<1>"))},
gv(a){return this.b===this.c},
gk(a){return(this.c-this.b&this.a.length-1)>>>0},
M(a,b){var s,r=this
A.om(b,r.gk(0),r,null,null)
s=r.a
s=s[(r.b+b&s.length-1)>>>0]
return s==null?r.$ti.c.a(s):s},
u(a,b){var s,r=this
for(s=r.b;s!==r.c;s=(s+1&r.a.length-1)>>>0)if(J.a_(r.a[s],b)){r.dg(s);++r.d
return!0}return!1},
i(a){return A.iX(this,"{","}")},
dg(a){var s,r,q,p=this,o=p.a,n=o.length-1,m=p.b,l=p.c
if((a-m&n)>>>0<(l-a&n)>>>0){for(s=a;s!==m;s=r){r=(s-1&n)>>>0
o[s]=o[r]}o[m]=null
p.b=(m+1&n)>>>0
return(a+1&n)>>>0}else{m=p.c=(l-1&n)>>>0
for(s=a;s!==m;s=q){q=(s+1&n)>>>0
o[s]=o[q]}o[m]=null
return a}}}
A.hu.prototype={
gm(){var s=this.e
return s==null?this.$ti.c.a(s):s},
l(){var s,r=this,q=r.a
if(r.c!==q.d)A.C(A.a5(q))
s=r.d
if(s===r.b){r.e=null
return!1}q=q.a
r.e=q[s]
r.d=(s+1&q.length-1)>>>0
return!0}}
A.cX.prototype={
gv(a){return this.a===0},
gao(a){return this.a!==0},
am(a,b){var s
for(s=J.ae(b);s.l();)this.E(0,s.gm())},
aR(a,b,c){return new A.bT(this,b,this.$ti.h("@<1>").X(c).h("bT<1,2>"))},
i(a){return A.iX(this,"{","}")},
ad(a,b){return A.oP(this,b,this.$ti.c)},
M(a,b){var s,r,q,p=this
A.ap(b,"index")
s=A.tF(p,p.r,p.$ti.c)
for(r=b;s.l();){if(r===0){q=s.d
return q==null?s.$ti.c.a(q):q}--r}throw A.a(A.fh(b,b-r,p,null,"index"))},
$ip:1,
$id:1,
$iby:1}
A.ex.prototype={}
A.hq.prototype={
j(a,b){var s,r=this.b
if(r==null)return this.c.j(0,b)
else if(typeof b!="string")return null
else{s=r[b]
return typeof s=="undefined"?this.hr(b):s}},
gk(a){return this.b==null?this.c.a:this.bW().length},
gv(a){return this.gk(0)===0},
ga_(){if(this.b==null){var s=this.c
return new A.b8(s,A.D(s).h("b8<1>"))}return new A.hr(this)},
N(a){if(this.b==null)return this.c.N(a)
return Object.prototype.hasOwnProperty.call(this.a,a)},
Z(a,b){var s,r,q,p,o=this
if(o.b==null)return o.c.Z(0,b)
s=o.bW()
for(r=0;r<s.length;++r){q=s[r]
p=o.b[q]
if(typeof p=="undefined"){p=A.mm(o.a[q])
o.b[q]=p}b.$2(q,p)
if(s!==o.c)throw A.a(A.a5(o))}},
bW(){var s=this.c
if(s==null)s=this.c=A.n(Object.keys(this.a),t.s)
return s},
hr(a){var s
if(!Object.prototype.hasOwnProperty.call(this.a,a))return null
s=A.mm(this.a[a])
return this.b[a]=s}}
A.hr.prototype={
gk(a){return this.a.gk(0)},
M(a,b){var s=this.a
return s.b==null?s.ga_().M(0,b):s.bW()[b]},
gt(a){var s=this.a
if(s.b==null){s=s.ga_()
s=s.gt(s)}else{s=s.bW()
s=new J.cG(s,s.length,A.ac(s).h("cG<1>"))}return s},
a5(a,b){return this.a.N(b)}}
A.mb.prototype={
$0(){var s,r
try{s=new TextDecoder("utf-8",{fatal:true})
return s}catch(r){}return null},
$S:31}
A.ma.prototype={
$0(){var s,r
try{s=new TextDecoder("utf-8",{fatal:false})
return s}catch(r){}return null},
$S:31}
A.hZ.prototype={
iP(a0,a1,a2){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a="Invalid base64 encoding length "
a2=A.c6(a1,a2,a0.length)
s=$.qB()
for(r=a1,q=r,p=null,o=-1,n=-1,m=0;r<a2;r=l){l=r+1
k=a0.charCodeAt(r)
if(k===37){j=l+2
if(j<=a2){i=A.mA(a0.charCodeAt(l))
h=A.mA(a0.charCodeAt(l+1))
g=i*16+h-(h&256)
if(g===37)g=-1
l=j}else g=-1}else g=k
if(0<=g&&g<=127){f=s[g]
if(f>=0){g="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".charCodeAt(f)
if(g===k)continue
k=g}else{if(f===-1){if(o<0){e=p==null?null:p.a.length
if(e==null)e=0
o=e+(r-q)
n=r}++m
if(k===61)continue}k=g}if(f!==-2){if(p==null){p=new A.ab("")
e=p}else e=p
e.a+=B.a.n(a0,q,r)
d=A.aX(k)
e.a+=d
q=l
continue}}throw A.a(A.a3("Invalid base64 data",a0,r))}if(p!=null){e=B.a.n(a0,q,a2)
e=p.a+=e
d=e.length
if(o>=0)A.o1(a0,n,a2,o,m,d)
else{c=B.b.a7(d-1,4)+1
if(c===1)throw A.a(A.a3(a,a0,a2))
while(c<4){e+="="
p.a=e;++c}}e=p.a
return B.a.aT(a0,a1,a2,e.charCodeAt(0)==0?e:e)}b=a2-a1
if(o>=0)A.o1(a0,n,a2,o,m,b)
else{c=B.b.a7(b,4)
if(c===1)throw A.a(A.a3(a,a0,a2))
if(c>1)a0=B.a.aT(a0,a2,a2,c===2?"==":"=")}return a0}}
A.f2.prototype={}
A.f7.prototype={}
A.bS.prototype={}
A.iB.prototype={}
A.dM.prototype={
i(a){var s=A.dD(this.a)
return(this.b!=null?"Converting object to an encodable object failed:":"Converting object did not return an encodable object:")+" "+s}}
A.ft.prototype={
i(a){return"Cyclic error in JSON stringify"}}
A.j_.prototype={
eH(a,b){var s=A.uN(a,this.gia().a)
return s},
ic(a,b){var s=A.tE(a,this.gie().b,null)
return s},
gie(){return B.b3},
gia(){return B.b2}}
A.fv.prototype={}
A.fu.prototype={}
A.lQ.prototype={
fb(a){var s,r,q,p,o,n=this,m=a.length
for(s=0,r=0;r<m;++r){q=a.charCodeAt(r)
if(q>92){if(q>=55296){p=q&64512
if(p===55296){o=r+1
o=!(o<m&&(a.charCodeAt(o)&64512)===56320)}else o=!1
if(!o)if(p===56320){p=r-1
p=!(p>=0&&(a.charCodeAt(p)&64512)===55296)}else p=!1
else p=!0
if(p){if(r>s)n.cC(a,s,r)
s=r+1
n.L(92)
n.L(117)
n.L(100)
p=q>>>8&15
n.L(p<10?48+p:87+p)
p=q>>>4&15
n.L(p<10?48+p:87+p)
p=q&15
n.L(p<10?48+p:87+p)}}continue}if(q<32){if(r>s)n.cC(a,s,r)
s=r+1
n.L(92)
switch(q){case 8:n.L(98)
break
case 9:n.L(116)
break
case 10:n.L(110)
break
case 12:n.L(102)
break
case 13:n.L(114)
break
default:n.L(117)
n.L(48)
n.L(48)
p=q>>>4&15
n.L(p<10?48+p:87+p)
p=q&15
n.L(p<10?48+p:87+p)
break}}else if(q===34||q===92){if(r>s)n.cC(a,s,r)
s=r+1
n.L(92)
n.L(q)}}if(s===0)n.a0(a)
else if(s<m)n.cC(a,s,m)},
cW(a){var s,r,q,p
for(s=this.a,r=s.length,q=0;q<r;++q){p=s[q]
if(a==null?p==null:a===p)throw A.a(new A.ft(a,null))}s.push(a)},
cB(a){var s,r,q,p,o=this
if(o.fa(a))return
o.cW(a)
try{s=o.b.$1(a)
if(!o.fa(s)){q=A.os(a,null,o.geh())
throw A.a(q)}o.a.pop()}catch(p){r=A.W(p)
q=A.os(a,r,o.geh())
throw A.a(q)}},
fa(a){var s,r=this
if(typeof a=="number"){if(!isFinite(a))return!1
r.jg(a)
return!0}else if(a===!0){r.a0("true")
return!0}else if(a===!1){r.a0("false")
return!0}else if(a==null){r.a0("null")
return!0}else if(typeof a=="string"){r.a0('"')
r.fb(a)
r.a0('"')
return!0}else if(t.j.b(a)){r.cW(a)
r.je(a)
r.a.pop()
return!0}else if(t._.b(a)){r.cW(a)
s=r.jf(a)
r.a.pop()
return s}else return!1},
je(a){var s,r,q=this
q.a0("[")
s=J.au(a)
if(s.gao(a)){q.cB(s.j(a,0))
for(r=1;r<s.gk(a);++r){q.a0(",")
q.cB(s.j(a,r))}}q.a0("]")},
jf(a){var s,r,q,p,o=this,n={}
if(a.gv(a)){o.a0("{}")
return!0}s=a.gk(a)*2
r=A.an(s,null,!1,t.X)
q=n.a=0
n.b=!0
a.Z(0,new A.lR(n,r))
if(!n.b)return!1
o.a0("{")
for(p='"';q<s;q+=2,p=',"'){o.a0(p)
o.fb(A.ah(r[q]))
o.a0('":')
o.cB(r[q+1])}o.a0("}")
return!0}}
A.lR.prototype={
$2(a,b){var s,r,q,p
if(typeof a!="string")this.a.b=!1
s=this.b
r=this.a
q=r.a
p=r.a=q+1
s[q]=a
r.a=p+1
s[p]=b},
$S:26}
A.lP.prototype={
geh(){var s=this.c
return s instanceof A.ab?s.i(0):null},
jg(a){this.c.bk(B.t.i(a))},
a0(a){this.c.bk(a)},
cC(a,b,c){this.c.bk(B.a.n(a,b,c))},
L(a){this.c.L(a)}}
A.jY.prototype={
cb(a){return new A.eK(!1).d0(a,0,null,!0)}}
A.h4.prototype={
ac(a){var s,r,q=A.c6(0,null,a.length)
if(q===0)return new Uint8Array(0)
s=new Uint8Array(q*3)
r=new A.mc(s)
if(r.fZ(a,0,q)!==q)r.dl()
return B.d.cR(s,0,r.b)}}
A.mc.prototype={
dl(){var s=this,r=s.c,q=s.b,p=s.b=q+1
r.$flags&2&&A.v(r)
r[q]=239
q=s.b=p+1
r[p]=191
s.b=q+1
r[q]=189},
hO(a,b){var s,r,q,p,o=this
if((b&64512)===56320){s=65536+((a&1023)<<10)|b&1023
r=o.c
q=o.b
p=o.b=q+1
r.$flags&2&&A.v(r)
r[q]=s>>>18|240
q=o.b=p+1
r[p]=s>>>12&63|128
p=o.b=q+1
r[q]=s>>>6&63|128
o.b=p+1
r[p]=s&63|128
return!0}else{o.dl()
return!1}},
fZ(a,b,c){var s,r,q,p,o,n,m,l,k=this
if(b!==c&&(a.charCodeAt(c-1)&64512)===55296)--c
for(s=k.c,r=s.$flags|0,q=s.length,p=b;p<c;++p){o=a.charCodeAt(p)
if(o<=127){n=k.b
if(n>=q)break
k.b=n+1
r&2&&A.v(s)
s[n]=o}else{n=o&64512
if(n===55296){if(k.b+4>q)break
m=p+1
if(k.hO(o,a.charCodeAt(m)))p=m}else if(n===56320){if(k.b+3>q)break
k.dl()}else if(o<=2047){n=k.b
l=n+1
if(l>=q)break
k.b=l
r&2&&A.v(s)
s[n]=o>>>6|192
k.b=l+1
s[l]=o&63|128}else{n=k.b
if(n+2>=q)break
l=k.b=n+1
r&2&&A.v(s)
s[n]=o>>>12|224
n=k.b=l+1
s[l]=o>>>6&63|128
k.b=n+1
s[n]=o&63|128}}}return p}}
A.eK.prototype={
d0(a,b,c,d){var s,r,q,p,o,n,m=this,l=A.c6(b,c,J.aw(a))
if(b===l)return""
if(a instanceof Uint8Array){s=a
r=s
q=0}else{r=A.u4(a,b,l)
l-=b
q=b
b=0}if(d&&l-b>=15){p=m.a
o=A.u3(p,r,b,l)
if(o!=null){if(!p)return o
if(o.indexOf("\ufffd")<0)return o}}o=m.d1(r,b,l,d)
p=m.b
if((p&1)!==0){n=A.u5(p)
m.b=0
throw A.a(A.a3(n,a,q+m.c))}return o},
d1(a,b,c,d){var s,r,q=this
if(c-b>1000){s=B.b.K(b+c,2)
r=q.d1(a,b,s,!1)
if((q.b&1)!==0)return r
return r+q.d1(a,s,c,d)}return q.i9(a,b,c,d)},
i9(a,b,c,d){var s,r,q,p,o,n,m,l=this,k=65533,j=l.b,i=l.c,h=new A.ab(""),g=b+1,f=a[b]
A:for(s=l.a;;){for(;;g=p){r="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFFFFFFFFFFFFFFFFGGGGGGGGGGGGGGGGHHHHHHHHHHHHHHHHHHHHHHHHHHHIHHHJEEBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBKCCCCCCCCCCCCDCLONNNMEEEEEEEEEEE".charCodeAt(f)&31
i=j<=32?f&61694>>>r:(f&63|i<<6)>>>0
j=" \x000:XECCCCCN:lDb \x000:XECCCCCNvlDb \x000:XECCCCCN:lDb AAAAA\x00\x00\x00\x00\x00AAAAA00000AAAAA:::::AAAAAGG000AAAAA00KKKAAAAAG::::AAAAA:IIIIAAAAA000\x800AAAAA\x00\x00\x00\x00 AAAAA".charCodeAt(j+r)
if(j===0){q=A.aX(i)
h.a+=q
if(g===c)break A
break}else if((j&1)!==0){if(s)switch(j){case 69:case 67:q=A.aX(k)
h.a+=q
break
case 65:q=A.aX(k)
h.a+=q;--g
break
default:q=A.aX(k)
h.a=(h.a+=q)+q
break}else{l.b=j
l.c=g-1
return""}j=0}if(g===c)break A
p=g+1
f=a[g]}p=g+1
f=a[g]
if(f<128){for(;;){if(!(p<c)){o=c
break}n=p+1
f=a[p]
if(f>=128){o=n-1
p=n
break}p=n}if(o-g<20)for(m=g;m<o;++m){q=A.aX(a[m])
h.a+=q}else{q=A.oS(a,g,o)
h.a+=q}if(o===c)break A
g=p}else g=p}if(d&&j>32)if(s){s=A.aX(k)
h.a+=s}else{l.b=77
l.c=c
return""}l.b=j
l.c=i
s=h.a
return s.charCodeAt(0)==0?s:s}}
A.U.prototype={
ah(a){var s,r,q=this,p=q.c
if(p===0)return q
s=!q.a
r=q.b
p=A.ar(p,r)
return new A.U(p===0?!1:s,r,p)},
fS(a){var s,r,q,p,o,n,m=this.c
if(m===0)return $.aM()
s=m+a
r=this.b
q=new Uint16Array(s)
for(p=m-1;p>=0;--p)q[p+a]=r[p]
o=this.a
n=A.ar(s,q)
return new A.U(n===0?!1:o,q,n)},
fT(a){var s,r,q,p,o,n,m,l=this,k=l.c
if(k===0)return $.aM()
s=k-a
if(s<=0)return l.a?$.nX():$.aM()
r=l.b
q=new Uint16Array(s)
for(p=a;p<k;++p)q[p-a]=r[p]
o=l.a
n=A.ar(s,q)
m=new A.U(n===0?!1:o,q,n)
if(o)for(p=0;p<a;++p)if(r[p]!==0)return m.cQ(0,$.eW())
return m},
aG(a,b){var s,r,q,p,o,n=this
if(b<0)throw A.a(A.M("shift-amount must be posititve "+b,null))
s=n.c
if(s===0)return n
r=B.b.K(b,16)
if(B.b.a7(b,16)===0)return n.fS(r)
q=s+r+1
p=new Uint16Array(q)
A.p7(n.b,s,b,p)
s=n.a
o=A.ar(q,p)
return new A.U(o===0?!1:s,p,o)},
aZ(a,b){var s,r,q,p,o,n,m,l,k,j=this
if(b<0)throw A.a(A.M("shift-amount must be posititve "+b,null))
s=j.c
if(s===0)return j
r=B.b.K(b,16)
q=B.b.a7(b,16)
if(q===0)return j.fT(r)
p=s-r
if(p<=0)return j.a?$.nX():$.aM()
o=j.b
n=new Uint16Array(p)
A.tx(o,s,b,n)
s=j.a
m=A.ar(p,n)
l=new A.U(m===0?!1:s,n,m)
if(s){if((o[r]&B.b.aG(1,q)-1)>>>0!==0)return l.cQ(0,$.eW())
for(k=0;k<r;++k)if(o[k]!==0)return l.cQ(0,$.eW())}return l},
ab(a,b){var s,r=this.a
if(r===b.a){s=A.kn(this.b,this.c,b.b,b.c)
return r?0-s:s}return r?-1:1},
cU(a,b){var s,r,q,p=this,o=p.c,n=a.c
if(o<n)return a.cU(p,b)
if(o===0)return $.aM()
if(n===0)return p.a===b?p:p.ah(0)
s=o+1
r=new Uint16Array(s)
A.tt(p.b,o,a.b,n,r)
q=A.ar(s,r)
return new A.U(q===0?!1:b,r,q)},
bU(a,b){var s,r,q,p=this,o=p.c
if(o===0)return $.aM()
s=a.c
if(s===0)return p.a===b?p:p.ah(0)
r=new Uint16Array(o)
A.hd(p.b,o,a.b,s,r)
q=A.ar(o,r)
return new A.U(q===0?!1:b,r,q)},
fc(a,b){var s,r,q=this,p=q.c
if(p===0)return b
s=b.c
if(s===0)return q
r=q.a
if(r===b.a)return q.cU(b,r)
if(A.kn(q.b,p,b.b,s)>=0)return q.bU(b,r)
return b.bU(q,!r)},
cQ(a,b){var s,r,q=this,p=q.c
if(p===0)return b.ah(0)
s=b.c
if(s===0)return q
r=q.a
if(r!==b.a)return q.cU(b,r)
if(A.kn(q.b,p,b.b,s)>=0)return q.bU(b,r)
return b.bU(q,!r)},
bn(a,b){var s,r,q,p,o,n,m,l=this.c,k=b.c
if(l===0||k===0)return $.aM()
s=l+k
r=this.b
q=b.b
p=new Uint16Array(s)
for(o=0;o<k;){A.p8(q[o],r,0,p,o,l);++o}n=this.a!==b.a
m=A.ar(s,p)
return new A.U(m===0?!1:n,p,m)},
fR(a){var s,r,q,p
if(this.c<a.c)return $.aM()
this.e9(a)
s=$.np.a9()-$.ed.a9()
r=A.nr($.no.a9(),$.ed.a9(),$.np.a9(),s)
q=A.ar(s,r)
p=new A.U(!1,r,q)
return this.a!==a.a&&q>0?p.ah(0):p},
hz(a){var s,r,q,p=this
if(p.c<a.c)return p
p.e9(a)
s=A.nr($.no.a9(),0,$.ed.a9(),$.ed.a9())
r=A.ar($.ed.a9(),s)
q=new A.U(!1,s,r)
if($.nq.a9()>0)q=q.aZ(0,$.nq.a9())
return p.a&&q.c>0?q.ah(0):q},
e9(a){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=this,b=c.c
if(b===$.p4&&a.c===$.p6&&c.b===$.p3&&a.b===$.p5)return
s=a.b
r=a.c
q=16-B.b.geE(s[r-1])
if(q>0){p=new Uint16Array(r+5)
o=A.p2(s,r,q,p)
n=new Uint16Array(b+5)
m=A.p2(c.b,b,q,n)}else{n=A.nr(c.b,0,b,b+2)
o=r
p=s
m=b}l=p[o-1]
k=m-o
j=new Uint16Array(m)
i=A.ns(p,o,k,j)
h=m+1
g=n.$flags|0
if(A.kn(n,m,j,i)>=0){g&2&&A.v(n)
n[m]=1
A.hd(n,h,j,i,n)}else{g&2&&A.v(n)
n[m]=0}f=new Uint16Array(o+2)
f[o]=1
A.hd(f,o+1,p,o,f)
e=m-1
while(k>0){d=A.tu(l,n,e);--k
A.p8(d,f,0,n,k,o)
if(n[e]<d){i=A.ns(f,o,k,j)
A.hd(n,h,j,i,n)
while(--d,n[e]<d)A.hd(n,h,j,i,n)}--e}$.p3=c.b
$.p4=b
$.p5=s
$.p6=r
$.no.b=n
$.np.b=h
$.ed.b=o
$.nq.b=q},
gF(a){var s,r,q,p=new A.ko(),o=this.c
if(o===0)return 6707
s=this.a?83585:429689
for(r=this.b,q=0;q<o;++q)s=p.$2(s,r[q])
return new A.kp().$1(s)},
a3(a,b){if(b==null)return!1
return b instanceof A.U&&this.ab(0,b)===0},
i(a){var s,r,q,p,o,n=this,m=n.c
if(m===0)return"0"
if(m===1){if(n.a)return B.b.i(-n.b[0])
return B.b.i(n.b[0])}s=A.n([],t.s)
m=n.a
r=m?n.ah(0):n
while(r.c>1){q=$.nW()
if(q.c===0)A.C(B.aH)
p=r.hz(q).i(0)
s.push(p)
o=p.length
if(o===1)s.push("000")
if(o===2)s.push("00")
if(o===3)s.push("0")
r=r.fR(q)}s.push(B.b.i(r.b[0]))
if(m)s.push("-")
return new A.dX(s,t.bJ).iH(0)}}
A.ko.prototype={
$2(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
$S:3}
A.kp.prototype={
$1(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
$S:14}
A.hj.prototype={
eJ(a){var s=this.a
if(s!=null)s.unregister(a)}}
A.dB.prototype={
a3(a,b){if(b==null)return!1
return b instanceof A.dB&&this.a===b.a&&this.b===b.b&&this.c===b.c},
gF(a){return A.n9(this.a,this.b,B.k,B.k)},
ab(a,b){var s=B.b.ab(this.a,b.a)
if(s!==0)return s
return B.b.ab(this.b,b.b)},
i(a){var s=this,r=A.ri(A.oG(s)),q=A.fb(A.oE(s)),p=A.fb(A.oB(s)),o=A.fb(A.oC(s)),n=A.fb(A.oD(s)),m=A.fb(A.oF(s)),l=A.of(A.rZ(s)),k=s.b,j=k===0?"":A.of(k)
k=r+"-"+q
if(s.c)return k+"-"+p+" "+o+":"+n+":"+m+"."+l+j+"Z"
else return k+"-"+p+" "+o+":"+n+":"+m+"."+l+j}}
A.dC.prototype={
a3(a,b){if(b==null)return!1
return b instanceof A.dC&&this.a===b.a},
gF(a){return B.b.gF(this.a)},
ab(a,b){return B.b.ab(this.a,b.a)},
i(a){var s,r,q,p,o,n=this.a,m=B.b.K(n,36e8),l=n%36e8
if(n<0){m=0-m
n=0-l
s="-"}else{n=l
s=""}r=B.b.K(n,6e7)
n%=6e7
q=r<10?"0":""
p=B.b.K(n,1e6)
o=p<10?"0":""
return s+m+":"+q+r+":"+o+p+"."+B.a.eR(B.b.i(n%1e6),6,"0")}}
A.kK.prototype={
i(a){return this.ae()}}
A.G.prototype={
gb_(){return A.rY(this)}}
A.eY.prototype={
i(a){var s=this.a
if(s!=null)return"Assertion failed: "+A.dD(s)
return"Assertion failed"}}
A.bd.prototype={}
A.aN.prototype={
gd3(){return"Invalid argument"+(!this.a?"(s)":"")},
gd2(){return""},
i(a){var s=this,r=s.c,q=r==null?"":" ("+r+")",p=s.d,o=p==null?"":": "+A.y(p),n=s.gd3()+q+o
if(!s.a)return n
return n+s.gd2()+": "+A.dD(s.gdD())},
gdD(){return this.b}}
A.cS.prototype={
gdD(){return this.b},
gd3(){return"RangeError"},
gd2(){var s,r=this.e,q=this.f
if(r==null)s=q!=null?": Not less than or equal to "+A.y(q):""
else if(q==null)s=": Not greater than or equal to "+A.y(r)
else if(q>r)s=": Not in inclusive range "+A.y(r)+".."+A.y(q)
else s=q<r?": Valid value range is empty":": Only valid value is "+A.y(r)
return s}}
A.dJ.prototype={
gdD(){return this.b},
gd3(){return"RangeError"},
gd2(){if(this.b<0)return": index must not be negative"
var s=this.f
if(s===0)return": no indices are valid"
return": index should be less than "+s},
gk(a){return this.f}}
A.e4.prototype={
i(a){return"Unsupported operation: "+this.a}}
A.fZ.prototype={
i(a){var s=this.a
return s!=null?"UnimplementedError: "+s:"UnimplementedError"}}
A.b0.prototype={
i(a){return"Bad state: "+this.a}}
A.f8.prototype={
i(a){var s=this.a
if(s==null)return"Concurrent modification during iteration."
return"Concurrent modification during iteration: "+A.dD(s)+"."}}
A.fJ.prototype={
i(a){return"Out of Memory"},
gb_(){return null},
$iG:1}
A.e0.prototype={
i(a){return"Stack Overflow"},
gb_(){return null},
$iG:1}
A.hi.prototype={
i(a){return"Exception: "+this.a},
$ia6:1}
A.aV.prototype={
i(a){var s,r,q,p,o,n,m,l,k,j,i,h=this.a,g=""!==h?"FormatException: "+h:"FormatException",f=this.c,e=this.b
if(typeof e=="string"){if(f!=null)s=f<0||f>e.length
else s=!1
if(s)f=null
if(f==null){if(e.length>78)e=B.a.n(e,0,75)+"..."
return g+"\n"+e}for(r=1,q=0,p=!1,o=0;o<f;++o){n=e.charCodeAt(o)
if(n===10){if(q!==o||!p)++r
q=o+1
p=!1}else if(n===13){++r
q=o+1
p=!0}}g=r>1?g+(" (at line "+r+", character "+(f-q+1)+")\n"):g+(" (at character "+(f+1)+")\n")
m=e.length
for(o=f;o<m;++o){n=e.charCodeAt(o)
if(n===10||n===13){m=o
break}}l=""
if(m-q>78){k="..."
if(f-q<75){j=q+75
i=q}else{if(m-f<75){i=m-75
j=m
k=""}else{i=f-36
j=f+36}l="..."}}else{j=m
i=q
k=""}return g+l+B.a.n(e,i,j)+k+"\n"+B.a.bn(" ",f-i+l.length)+"^\n"}else return f!=null?g+(" (at offset "+A.y(f)+")"):g},
$ia6:1}
A.fk.prototype={
gb_(){return null},
i(a){return"IntegerDivisionByZeroException"},
$iG:1,
$ia6:1}
A.d.prototype={
aR(a,b,c){return A.rI(this,b,A.D(this).h("d.E"),c)},
bj(a,b){var s=A.D(this).h("d.E")
if(b)s=A.b9(this,s)
else{s=A.b9(this,s)
s.$flags=1
s=s}return s},
f5(a){return this.bj(0,!0)},
gk(a){var s,r=this.gt(this)
for(s=0;r.l();)++s
return s},
gv(a){return!this.gt(this).l()},
gao(a){return!this.gv(this)},
ad(a,b){return A.oP(this,b,A.D(this).h("d.E"))},
M(a,b){var s,r
A.ap(b,"index")
s=this.gt(this)
for(r=b;s.l();){if(r===0)return s.gm();--r}throw A.a(A.fh(b,b-r,this,null,"index"))},
i(a){return A.ry(this,"(",")")}}
A.ao.prototype={
i(a){return"MapEntry("+A.y(this.a)+": "+A.y(this.b)+")"}}
A.B.prototype={
gF(a){return A.l.prototype.gF.call(this,0)},
i(a){return"null"}}
A.l.prototype={$il:1,
a3(a,b){return this===b},
gF(a){return A.dW(this)},
i(a){return"Instance of '"+A.fM(this)+"'"},
gS(a){return A.vi(this)},
toString(){return this.i(this)}}
A.hE.prototype={
i(a){return""},
$ia0:1}
A.ab.prototype={
gk(a){return this.a.length},
bk(a){var s=A.y(a)
this.a+=s},
L(a){var s=A.aX(a)
this.a+=s},
i(a){var s=this.a
return s.charCodeAt(0)==0?s:s}}
A.jW.prototype={
$2(a,b){throw A.a(A.a3("Illegal IPv6 address, "+a,this.a,b))},
$S:47}
A.eH.prototype={
ger(){var s,r,q,p,o=this,n=o.w
if(n===$){s=o.a
r=s.length!==0?s+":":""
q=o.c
p=q==null
if(!p||s==="file"){s=r+"//"
r=o.b
if(r.length!==0)s=s+r+"@"
if(!p)s+=q
r=o.d
if(r!=null)s=s+":"+A.y(r)}else s=r
s+=o.e
r=o.f
if(r!=null)s=s+"?"+r
r=o.r
if(r!=null)s=s+"#"+r
n=o.w=s.charCodeAt(0)==0?s:s}return n},
giU(){var s,r,q=this,p=q.x
if(p===$){s=q.e
if(s.length!==0&&s.charCodeAt(0)===47)s=B.a.T(s,1)
r=s.length===0?B.u:A.j1(new A.aa(A.n(s.split("/"),t.s),A.v8(),t.do),t.N)
q.x!==$&&A.qh()
p=q.x=r}return p},
gF(a){var s,r=this,q=r.y
if(q===$){s=B.a.gF(r.ger())
r.y!==$&&A.qh()
r.y=s
q=s}return q},
gdR(){return this.b},
gbI(){var s=this.c
if(s==null)return""
if(B.a.A(s,"[")&&!B.a.D(s,"v",1))return B.a.n(s,1,s.length-1)
return s},
gbL(){var s=this.d
return s==null?A.ps(this.a):s},
gbN(){var s=this.f
return s==null?"":s},
gce(){var s=this.r
return s==null?"":s},
iG(a){var s=this.a
if(a.length!==s.length)return!1
return A.uj(a,s,0)>=0},
eX(a){var s,r,q,p,o,n,m,l=this
a=A.nA(a,0,a.length)
s=a==="file"
r=l.b
q=l.d
if(a!==l.a)q=A.m9(q,a)
p=l.c
if(!(p!=null))p=r.length!==0||q!=null||s?"":null
o=l.e
if(!s)n=p!=null&&o.length!==0
else n=!0
if(n&&!B.a.A(o,"/"))o="/"+o
m=o
return A.eI(a,r,p,q,m,l.f,l.r)},
geO(){if(this.a!==""){var s=this.r
s=(s==null?"":s)===""}else s=!1
return s},
eg(a,b){var s,r,q,p,o,n,m
for(s=0,r=0;B.a.D(b,"../",r);){r+=3;++s}q=B.a.dF(a,"/")
for(;;){if(!(q>0&&s>0))break
p=B.a.eP(a,"/",q-1)
if(p<0)break
o=q-p
n=o!==2
m=!1
if(!n||o===3)if(a.charCodeAt(p+1)===46)n=!n||a.charCodeAt(p+2)===46
else n=m
else n=m
if(n)break;--s
q=p}return B.a.aT(a,q+1,null,B.a.T(b,r-3*s))},
f_(a){return this.bO(A.jV(a))},
bO(a){var s,r,q,p,o,n,m,l,k,j,i,h=this
if(a.gaX().length!==0)return a
else{s=h.a
if(a.gdw()){r=a.eX(s)
return r}else{q=h.b
p=h.c
o=h.d
n=h.e
if(a.geM())m=a.gcn()?a.gbN():h.f
else{l=A.u1(h,n)
if(l>0){k=B.a.n(n,0,l)
n=a.gdv()?k+A.cr(a.gag()):k+A.cr(h.eg(B.a.T(n,k.length),a.gag()))}else if(a.gdv())n=A.cr(a.gag())
else if(n.length===0)if(p==null)n=s.length===0?a.gag():A.cr(a.gag())
else n=A.cr("/"+a.gag())
else{j=h.eg(n,a.gag())
r=s.length===0
if(!r||p!=null||B.a.A(n,"/"))n=A.cr(j)
else n=A.nC(j,!r||p!=null)}m=a.gcn()?a.gbN():null}}}i=a.gdz()?a.gce():null
return A.eI(s,q,p,o,n,m,i)},
gdw(){return this.c!=null},
gcn(){return this.f!=null},
gdz(){return this.r!=null},
geM(){return this.e.length===0},
gdv(){return B.a.A(this.e,"/")},
dP(){var s,r=this,q=r.a
if(q!==""&&q!=="file")throw A.a(A.Y("Cannot extract a file path from a "+q+" URI"))
q=r.f
if((q==null?"":q)!=="")throw A.a(A.Y(u.y))
q=r.r
if((q==null?"":q)!=="")throw A.a(A.Y(u.l))
if(r.c!=null&&r.gbI()!=="")A.C(A.Y(u.j))
s=r.giU()
A.tX(s,!1)
q=A.ng(B.a.A(r.e,"/")?"/":"",s,"/")
q=q.charCodeAt(0)==0?q:q
return q},
i(a){return this.ger()},
a3(a,b){var s,r,q,p=this
if(b==null)return!1
if(p===b)return!0
s=!1
if(t.dD.b(b))if(p.a===b.gaX())if(p.c!=null===b.gdw())if(p.b===b.gdR())if(p.gbI()===b.gbI())if(p.gbL()===b.gbL())if(p.e===b.gag()){r=p.f
q=r==null
if(!q===b.gcn()){if(q)r=""
if(r===b.gbN()){r=p.r
q=r==null
if(!q===b.gdz()){s=q?"":r
s=s===b.gce()}}}}return s},
$ih2:1,
gaX(){return this.a},
gag(){return this.e}}
A.jU.prototype={
gf7(){var s,r,q,p,o=this,n=null,m=o.c
if(m==null){m=o.a
s=o.b[0]+1
r=B.a.aP(m,"?",s)
q=m.length
if(r>=0){p=A.eJ(m,r+1,q,256,!1,!1)
q=r}else p=n
m=o.c=new A.hf("data","",n,n,A.eJ(m,s,q,128,!1,!1),p,n)}return m},
i(a){var s=this.a
return this.b[0]===-1?"data:"+s:s}}
A.aI.prototype={
gdw(){return this.c>0},
gdA(){return this.c>0&&this.d+1<this.e},
gcn(){return this.f<this.r},
gdz(){return this.r<this.a.length},
gdv(){return B.a.D(this.a,"/",this.e)},
geM(){return this.e===this.f},
geO(){return this.b>0&&this.r>=this.a.length},
gaX(){var s=this.w
return s==null?this.w=this.fN():s},
fN(){var s,r=this,q=r.b
if(q<=0)return""
s=q===4
if(s&&B.a.A(r.a,"http"))return"http"
if(q===5&&B.a.A(r.a,"https"))return"https"
if(s&&B.a.A(r.a,"file"))return"file"
if(q===7&&B.a.A(r.a,"package"))return"package"
return B.a.n(r.a,0,q)},
gdR(){var s=this.c,r=this.b+3
return s>r?B.a.n(this.a,r,s-1):""},
gbI(){var s=this.c
return s>0?B.a.n(this.a,s,this.d):""},
gbL(){var s,r=this
if(r.gdA())return A.vo(B.a.n(r.a,r.d+1,r.e))
s=r.b
if(s===4&&B.a.A(r.a,"http"))return 80
if(s===5&&B.a.A(r.a,"https"))return 443
return 0},
gag(){return B.a.n(this.a,this.e,this.f)},
gbN(){var s=this.f,r=this.r
return s<r?B.a.n(this.a,s+1,r):""},
gce(){var s=this.r,r=this.a
return s<r.length?B.a.T(r,s+1):""},
ee(a){var s=this.d+1
return s+a.length===this.e&&B.a.D(this.a,a,s)},
j0(){var s=this,r=s.r,q=s.a
if(r>=q.length)return s
return new A.aI(B.a.n(q,0,r),s.b,s.c,s.d,s.e,s.f,r,s.w)},
eX(a){var s,r,q,p,o,n,m,l,k,j,i,h=this,g=null
a=A.nA(a,0,a.length)
s=!(h.b===a.length&&B.a.A(h.a,a))
r=a==="file"
q=h.c
p=q>0?B.a.n(h.a,h.b+3,q):""
o=h.gdA()?h.gbL():g
if(s)o=A.m9(o,a)
q=h.c
if(q>0)n=B.a.n(h.a,q,h.d)
else n=p.length!==0||o!=null||r?"":g
q=h.a
m=h.f
l=B.a.n(q,h.e,m)
if(!r)k=n!=null&&l.length!==0
else k=!0
if(k&&!B.a.A(l,"/"))l="/"+l
k=h.r
j=m<k?B.a.n(q,m+1,k):g
m=h.r
i=m<q.length?B.a.T(q,m+1):g
return A.eI(a,p,n,o,l,j,i)},
f_(a){return this.bO(A.jV(a))},
bO(a){if(a instanceof A.aI)return this.hJ(this,a)
return this.eu().bO(a)},
hJ(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=b.b
if(c>0)return b
s=b.c
if(s>0){r=a.b
if(r<=0)return b
q=r===4
if(q&&B.a.A(a.a,"file"))p=b.e!==b.f
else if(q&&B.a.A(a.a,"http"))p=!b.ee("80")
else p=!(r===5&&B.a.A(a.a,"https"))||!b.ee("443")
if(p){o=r+1
return new A.aI(B.a.n(a.a,0,o)+B.a.T(b.a,c+1),r,s+o,b.d+o,b.e+o,b.f+o,b.r+o,a.w)}else return this.eu().bO(b)}n=b.e
c=b.f
if(n===c){s=b.r
if(c<s){r=a.f
o=r-c
return new A.aI(B.a.n(a.a,0,r)+B.a.T(b.a,c),a.b,a.c,a.d,a.e,c+o,s+o,a.w)}c=b.a
if(s<c.length){r=a.r
return new A.aI(B.a.n(a.a,0,r)+B.a.T(c,s),a.b,a.c,a.d,a.e,a.f,s+(r-s),a.w)}return a.j0()}s=b.a
if(B.a.D(s,"/",n)){m=a.e
l=A.pl(this)
k=l>0?l:m
o=k-n
return new A.aI(B.a.n(a.a,0,k)+B.a.T(s,n),a.b,a.c,a.d,m,c+o,b.r+o,a.w)}j=a.e
i=a.f
if(j===i&&a.c>0){while(B.a.D(s,"../",n))n+=3
o=j-n+1
return new A.aI(B.a.n(a.a,0,j)+"/"+B.a.T(s,n),a.b,a.c,a.d,j,c+o,b.r+o,a.w)}h=a.a
l=A.pl(this)
if(l>=0)g=l
else for(g=j;B.a.D(h,"../",g);)g+=3
f=0
for(;;){e=n+3
if(!(e<=c&&B.a.D(s,"../",n)))break;++f
n=e}for(d="";i>g;){--i
if(h.charCodeAt(i)===47){if(f===0){d="/"
break}--f
d="/"}}if(i===g&&a.b<=0&&!B.a.D(h,"/",j)){n-=f*3
d=""}o=i-n+d.length
return new A.aI(B.a.n(h,0,i)+d+B.a.T(s,n),a.b,a.c,a.d,j,c+o,b.r+o,a.w)},
dP(){var s,r=this,q=r.b
if(q>=0){s=!(q===4&&B.a.A(r.a,"file"))
q=s}else q=!1
if(q)throw A.a(A.Y("Cannot extract a file path from a "+r.gaX()+" URI"))
q=r.f
s=r.a
if(q<s.length){if(q<r.r)throw A.a(A.Y(u.y))
throw A.a(A.Y(u.l))}if(r.c<r.d)A.C(A.Y(u.j))
q=B.a.n(s,r.e,q)
return q},
gF(a){var s=this.x
return s==null?this.x=B.a.gF(this.a):s},
a3(a,b){if(b==null)return!1
if(this===b)return!0
return t.dD.b(b)&&this.a===b.i(0)},
eu(){var s=this,r=null,q=s.gaX(),p=s.gdR(),o=s.c>0?s.gbI():r,n=s.gdA()?s.gbL():r,m=s.a,l=s.f,k=B.a.n(m,s.e,l),j=s.r
l=l<j?s.gbN():r
return A.eI(q,p,o,n,k,l,j<m.length?s.gce():r)},
i(a){return this.a},
$ih2:1}
A.hf.prototype={}
A.fe.prototype={
i(a){return"Expando:null"}}
A.fH.prototype={
i(a){return"Promise was rejected with a value of `"+(this.a?"undefined":"null")+"`."},
$ia6:1}
A.iK.prototype={
$2(a,b){this.a.bi(new A.iI(a),new A.iJ(b),t.X)},
$S:83}
A.iI.prototype={
$1(a){var s=this.a
return s.call(s)},
$S:45}
A.iJ.prototype={
$2(a,b){var s,r,q=t.g.a(v.G.Error),p=A.cw(q,["Dart exception thrown from converted Future. Use the properties 'error' to fetch the boxed error and 'stack' to recover the stack trace."])
if(t.aX.b(a))A.C("Attempting to box non-Dart object.")
s={}
s[$.qJ()]=a
p.error=s
p.stack=b.i(0)
r=this.a
r.call(r,p)},
$S:12}
A.mF.prototype={
$1(a){var s,r,q,p
if(A.pU(a))return a
s=this.a
if(s.N(a))return s.j(0,a)
if(t._.b(a)){r={}
s.p(0,a,r)
for(s=J.ae(a.ga_());s.l();){q=s.gm()
r[q]=this.$1(a.j(0,q))}return r}else if(t.hf.b(a)){p=[]
s.p(0,a,p)
B.c.am(p,J.o0(a,this,t.z))
return p}else return a},
$S:21}
A.mJ.prototype={
$1(a){return this.a.O(a)},
$S:6}
A.mK.prototype={
$1(a){if(a==null)return this.a.a4(new A.fH(a===undefined))
return this.a.a4(a)},
$S:6}
A.mw.prototype={
$1(a){var s,r,q,p,o,n,m,l,k,j,i
if(A.pT(a))return a
s=this.a
a.toString
if(s.N(a))return s.j(0,a)
if(a instanceof Date)return new A.dB(A.og(a.getTime(),0,!0),0,!0)
if(a instanceof RegExp)throw A.a(A.M("structured clone of RegExp",null))
if(a instanceof Promise)return A.Q(a,t.X)
r=Object.getPrototypeOf(a)
if(r===Object.prototype||r===null){q=t.X
p=A.a4(q,q)
s.p(0,a,p)
o=Object.keys(a)
n=[]
for(s=J.bj(o),q=s.gt(o);q.l();)n.push(A.q6(q.gm()))
for(m=0;m<s.gk(o);++m){l=s.j(o,m)
k=n[m]
if(l!=null)p.p(0,k,this.$1(a[l]))}return p}if(a instanceof Array){j=a
p=[]
s.p(0,a,p)
i=a.length
for(s=J.au(j),m=0;m<i;++m)p.push(this.$1(s.j(j,m)))
return p}return a},
$S:21}
A.lM.prototype={
bK(a){if(a<=0||a>4294967296)throw A.a(A.na(u.w+a))
return Math.random()*a>>>0}}
A.lN.prototype={
fB(){var s=self.crypto
if(s!=null)if(s.getRandomValues!=null)return
throw A.a(A.Y("No source of cryptographically secure random numbers available."))},
bK(a){var s,r,q,p,o,n,m,l
if(a<=0||a>4294967296)throw A.a(A.na(u.w+a))
if(a>255)if(a>65535)s=a>16777215?4:3
else s=2
else s=1
r=this.a
r.$flags&2&&A.v(r,11)
r.setUint32(0,0,!1)
q=4-s
p=A.r(Math.pow(256,s))
for(o=a-1,n=(a&o)>>>0===0;;){crypto.getRandomValues(J.cE(B.bc.gaa(r),q,s))
m=r.getUint32(0,!1)
if(n)return(m&o)>>>0
l=m%a
if(m-l+a<p)return l}}}
A.fG.prototype={}
A.h1.prototype={}
A.jl.prototype={}
A.f9.prototype={
al(a){var s,r,q=t.G
A.q1("absolute",A.n([a,null,null,null,null,null,null,null,null,null,null,null,null,null,null],q))
s=this.a
s=s.P(a)>0&&!s.a6(a)
if(s)return a
s=this.b
r=A.n([s==null?A.va():s,a,null,null,null,null,null,null,null,null,null,null,null,null,null,null],q)
A.q1("join",r)
return this.iI(new A.ea(r,t.eJ))},
iI(a){var s,r,q,p,o,n,m,l,k
for(s=a.gt(0),r=new A.e9(s,new A.ic()),q=this.a,p=!1,o=!1,n="";r.l();){m=s.gm()
if(q.a6(m)&&o){l=A.fK(m,q)
k=n.charCodeAt(0)==0?n:n
n=B.a.n(k,0,q.bh(k,!0))
l.b=n
if(q.bJ(n))l.e[0]=q.gaY()
n=l.i(0)}else if(q.P(m)>0){o=!q.a6(m)
n=m}else{if(!(m.length!==0&&q.dr(m[0])))if(p)n+=q.gaY()
n+=m}p=q.bJ(m)}return n.charCodeAt(0)==0?n:n},
cM(a,b){var s=A.fK(b,this.a),r=s.d,q=A.ac(r).h("e8<1>")
r=A.b9(new A.e8(r,new A.id(),q),q.h("d.E"))
s.d=r
q=s.b
if(q!=null)B.c.iC(r,0,q)
return s.d},
cr(a){var s
if(!this.hf(a))return a
s=A.fK(a,this.a)
s.dH()
return s.i(0)},
hf(a){var s,r,q,p,o,n,m,l=this.a,k=l.P(a)
if(k!==0){if(l===$.hK())for(s=0;s<k;++s)if(a.charCodeAt(s)===47)return!0
r=k
q=47}else{r=0
q=null}for(p=a.length,s=r,o=null;s<p;++s,o=q,q=n){n=a.charCodeAt(s)
if(l.C(n)){if(l===$.hK()&&n===47)return!0
if(q!=null&&l.C(q))return!0
if(q===46)m=o==null||o===46||l.C(o)
else m=!1
if(m)return!0}}if(q==null)return!0
if(l.C(q))return!0
if(q===46)l=o==null||l.C(o)||o===46
else l=!1
if(l)return!0
return!1},
eU(a,b){var s,r,q,p,o,n=this,m='Unable to find a path to "'
b=n.al(b)
s=n.a
if(s.P(b)<=0&&s.P(a)>0)return n.cr(a)
if(s.P(a)<=0||s.a6(a))a=n.al(a)
if(s.P(a)<=0&&s.P(b)>0)throw A.a(A.oy(m+a+'" from "'+b+'".'))
r=A.fK(b,s)
r.dH()
q=A.fK(a,s)
q.dH()
p=r.d
if(p.length!==0&&p[0]===".")return q.i(0)
p=r.b
o=q.b
if(p!=o)p=p==null||o==null||!s.dI(p,o)
else p=!1
if(p)return q.i(0)
for(;;){p=r.d
if(p.length!==0){o=q.d
p=o.length!==0&&s.dI(p[0],o[0])}else p=!1
if(!p)break
B.c.cw(r.d,0)
B.c.cw(r.e,1)
B.c.cw(q.d,0)
B.c.cw(q.e,1)}p=r.d
o=p.length
if(o!==0&&p[0]==="..")throw A.a(A.oy(m+a+'" from "'+b+'".'))
p=t.N
B.c.dB(q.d,0,A.an(o,"..",!1,p))
o=q.e
o[0]=""
B.c.dB(o,1,A.an(r.d.length,s.gaY(),!1,p))
s=q.d
p=s.length
if(p===0)return"."
if(p>1&&B.c.gap(s)==="."){B.c.eV(q.d)
s=q.e
s.pop()
s.pop()
s.push("")}q.b=""
q.eW()
return q.i(0)},
hc(a,b){var s,r,q,p,o,n,m,l,k=this
a=a
b=b
r=k.a
q=r.P(a)>0
p=r.P(b)>0
if(q&&!p){b=k.al(b)
if(r.a6(a))a=k.al(a)}else if(p&&!q){a=k.al(a)
if(r.a6(b))b=k.al(b)}else if(p&&q){o=r.a6(b)
n=r.a6(a)
if(o&&!n)b=k.al(b)
else if(n&&!o)a=k.al(a)}m=k.hd(a,b)
if(m!==B.j)return m
s=null
try{s=k.eU(b,a)}catch(l){if(A.W(l) instanceof A.dV)return B.i
else throw l}if(r.P(s)>0)return B.i
if(J.a_(s,"."))return B.I
if(J.a_(s,".."))return B.i
return J.aw(s)>=3&&J.qZ(s,"..")&&r.C(J.qS(s,2))?B.i:B.J},
hd(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e=this
if(a===".")a=""
s=e.a
r=s.P(a)
q=s.P(b)
if(r!==q)return B.i
for(p=0;p<r;++p)if(!s.c6(a.charCodeAt(p),b.charCodeAt(p)))return B.i
o=b.length
n=a.length
m=q
l=r
k=47
j=null
for(;;){if(!(l<n&&m<o))break
A:{i=a.charCodeAt(l)
h=b.charCodeAt(m)
if(s.c6(i,h)){if(s.C(i))j=l;++l;++m
k=i
break A}if(s.C(i)&&s.C(k)){g=l+1
j=l
l=g
break A}else if(s.C(h)&&s.C(k)){++m
break A}if(i===46&&s.C(k)){++l
if(l===n)break
i=a.charCodeAt(l)
if(s.C(i)){g=l+1
j=l
l=g
break A}if(i===46){++l
if(l===n||s.C(a.charCodeAt(l)))return B.j}}if(h===46&&s.C(k)){++m
if(m===o)break
h=b.charCodeAt(m)
if(s.C(h)){++m
break A}if(h===46){++m
if(m===o||s.C(b.charCodeAt(m)))return B.j}}if(e.bY(b,m)!==B.F)return B.j
if(e.bY(a,l)!==B.F)return B.j
return B.i}}if(m===o){if(l===n||s.C(a.charCodeAt(l)))j=l
else if(j==null)j=Math.max(0,r-1)
f=e.bY(a,j)
if(f===B.G)return B.I
return f===B.H?B.j:B.i}f=e.bY(b,m)
if(f===B.G)return B.I
if(f===B.H)return B.j
return s.C(b.charCodeAt(m))||s.C(k)?B.J:B.i},
bY(a,b){var s,r,q,p,o,n,m
for(s=a.length,r=this.a,q=b,p=0,o=!1;q<s;){for(;;){if(!(q<s&&r.C(a.charCodeAt(q))))break;++q}if(q===s)break
n=q
for(;;){if(!(n<s&&!r.C(a.charCodeAt(n))))break;++n}m=n-q
if(!(m===1&&a.charCodeAt(q)===46))if(m===2&&a.charCodeAt(q)===46&&a.charCodeAt(q+1)===46){--p
if(p<0)break
if(p===0)o=!0}else ++p
if(n===s)break
q=n+1}if(p<0)return B.H
if(p===0)return B.G
if(o)return B.bx
return B.F}}
A.ic.prototype={
$1(a){return a!==""},
$S:22}
A.id.prototype={
$1(a){return a.length!==0},
$S:22}
A.mq.prototype={
$1(a){return a==null?"null":'"'+a+'"'},
$S:49}
A.de.prototype={
i(a){return this.a}}
A.df.prototype={
i(a){return this.a}}
A.iW.prototype={
fg(a){var s=this.P(a)
if(s>0)return B.a.n(a,0,s)
return this.a6(a)?a[0]:null},
c6(a,b){return a===b},
dI(a,b){return a===b}}
A.ja.prototype={
eW(){var s,r,q=this
for(;;){s=q.d
if(!(s.length!==0&&B.c.gap(s)===""))break
B.c.eV(q.d)
q.e.pop()}s=q.e
r=s.length
if(r!==0)s[r-1]=""},
dH(){var s,r,q,p,o,n=this,m=A.n([],t.s)
for(s=n.d,r=s.length,q=0,p=0;p<s.length;s.length===r||(0,A.R)(s),++p){o=s[p]
if(!(o==="."||o===""))if(o==="..")if(m.length!==0)m.pop()
else ++q
else m.push(o)}if(n.b==null)B.c.dB(m,0,A.an(q,"..",!1,t.N))
if(m.length===0&&n.b==null)m.push(".")
n.d=m
s=n.a
n.e=A.an(m.length+1,s.gaY(),!0,t.N)
r=n.b
if(r==null||m.length===0||!s.bJ(r))n.e[0]=""
r=n.b
if(r!=null&&s===$.hK())n.b=A.vW(r,"/","\\")
n.eW()},
i(a){var s,r,q,p,o=this.b
o=o!=null?o:""
for(s=this.d,r=s.length,q=this.e,p=0;p<r;++p)o=o+q[p]+s[p]
o+=B.c.gap(q)
return o.charCodeAt(0)==0?o:o}}
A.dV.prototype={
i(a){return"PathException: "+this.a},
$ia6:1}
A.jE.prototype={
i(a){return this.gdG()}}
A.jb.prototype={
dr(a){return B.a.a5(a,"/")},
C(a){return a===47},
bJ(a){var s=a.length
return s!==0&&a.charCodeAt(s-1)!==47},
bh(a,b){if(a.length!==0&&a.charCodeAt(0)===47)return 1
return 0},
P(a){return this.bh(a,!1)},
a6(a){return!1},
gdG(){return"posix"},
gaY(){return"/"}}
A.jX.prototype={
dr(a){return B.a.a5(a,"/")},
C(a){return a===47},
bJ(a){var s=a.length
if(s===0)return!1
if(a.charCodeAt(s-1)!==47)return!0
return B.a.eK(a,"://")&&this.P(a)===s},
bh(a,b){var s,r,q,p=a.length
if(p===0)return 0
if(a.charCodeAt(0)===47)return 1
for(s=0;s<p;++s){r=a.charCodeAt(s)
if(r===47)return 0
if(r===58){if(s===0)return 0
q=B.a.aP(a,"/",B.a.D(a,"//",s+1)?s+3:s)
if(q<=0)return p
if(!b||p<q+3)return q
if(!B.a.A(a,"file://"))return q
p=A.vc(a,q+1)
return p==null?q:p}}return 0},
P(a){return this.bh(a,!1)},
a6(a){return a.length!==0&&a.charCodeAt(0)===47},
gdG(){return"url"},
gaY(){return"/"}}
A.kc.prototype={
dr(a){return B.a.a5(a,"/")},
C(a){return a===47||a===92},
bJ(a){var s=a.length
if(s===0)return!1
s=a.charCodeAt(s-1)
return!(s===47||s===92)},
bh(a,b){var s,r=a.length
if(r===0)return 0
if(a.charCodeAt(0)===47)return 1
if(a.charCodeAt(0)===92){if(r<2||a.charCodeAt(1)!==92)return 1
s=B.a.aP(a,"\\",2)
if(s>0){s=B.a.aP(a,"\\",s+1)
if(s>0)return s}return r}if(r<3)return 0
if(!A.q8(a.charCodeAt(0)))return 0
if(a.charCodeAt(1)!==58)return 0
r=a.charCodeAt(2)
if(!(r===47||r===92))return 0
return 3},
P(a){return this.bh(a,!1)},
a6(a){return this.P(a)===1},
c6(a,b){var s
if(a===b)return!0
if(a===47)return b===92
if(a===92)return b===47
if((a^b)!==32)return!1
s=a|32
return s>=97&&s<=122},
dI(a,b){var s,r
if(a===b)return!0
s=a.length
if(s!==b.length)return!1
for(r=0;r<s;++r)if(!this.c6(a.charCodeAt(r),b.charCodeAt(r)))return!1
return!0},
gdG(){return"windows"},
gaY(){return"\\"}}
A.mL.prototype={
$1(a){var s,r,q,p,o=null,n=t.d1,m=n.a(B.q.eH(A.ah(a.j(0,0)),o)),l=n.a(B.q.eH(A.ah(a.j(0,1)),o)),k=A.a4(t.N,t.z)
for(n=l.gbF(),n=n.gt(n);n.l();){s=n.gm()
r=s.a
q=m.j(0,r)
p=s.b
if(!J.a_(p,q))k.p(0,r,p)}for(n=J.ae(m.ga_());n.l();){s=n.gm()
if(!l.N(s))k.p(0,s,o)}return B.q.ic(k,o)},
$S:8}
A.jc.prototype={
aC(a,b,c,d){return this.iT(a,b,c,d)},
iT(a,b,c,d){var s=0,r=A.j(t.u),q,p=this,o
var $async$aC=A.k(function(e,f){if(e===1)return A.f(f,r)
for(;;)switch(s){case 0:s=3
return A.c(p.fo(a,b,c,d),$async$aC)
case 3:o=f
A.vU(o.a)
q=o
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$aC,r)},
bG(a,b){throw A.a(A.nl(null))}}
A.mM.prototype={
$1(a){return this.a.f9()},
$S:8}
A.mN.prototype={
$1(a){return this.a.f9()},
$S:8}
A.mO.prototype={
$1(a){return A.r(a.j(0,0))},
$S:55}
A.mP.prototype={
$1(a){return"N/A"},
$S:8}
A.cZ.prototype={
ae(){return"SqliteUpdateKind."+this.b}}
A.aG.prototype={
gF(a){return A.n9(this.a,this.b,this.c,B.k)},
a3(a,b){if(b==null)return!1
return b instanceof A.aG&&b.a===this.a&&b.b===this.b&&b.c===this.c},
i(a){return"SqliteUpdate: "+this.a.i(0)+" on "+this.b+", rowid = "+this.c}}
A.ca.prototype={
i(a){var s,r,q=this,p=q.e
p=p==null?"":"while "+p+", "
p="SqliteException("+q.c+"): "+p+q.a
s=q.b
if(s!=null)p=p+", "+s
s=q.f
if(s!=null){r=q.d
r=r!=null?" (at position "+A.y(r)+"): ":": "
s=p+"\n  Causing statement"+r+s
p=q.r
p=p!=null?s+(", parameters: "+new A.aa(p,new A.jx(),A.ac(p).h("aa<1,o>")).bd(0,", ")):s}return p.charCodeAt(0)==0?p:p},
$ia6:1}
A.jx.prototype={
$1(a){if(t.p.b(a))return"blob ("+a.length+" bytes)"
else return J.bl(a)},
$S:59}
A.cF.prototype={}
A.jg.prototype={}
A.fW.prototype={}
A.jh.prototype={}
A.jj.prototype={}
A.ji.prototype={}
A.cT.prototype={}
A.cU.prototype={}
A.ff.prototype={
an(){var s,r,q,p,o,n,m=this
for(s=m.d,r=s.length,q=0;q<s.length;s.length===r||(0,A.R)(s),++q){p=s[q]
if(!p.d){p.d=!0
if(!p.c){o=p.b
o.c.d.sqlite3_reset(o.b)
p.c=!0}o=p.b
o.ca()
o.c.d.sqlite3_finalize(o.b)}}s=m.e
s=A.n(s.slice(0),A.ac(s))
r=s.length
q=0
for(;q<s.length;s.length===r||(0,A.R)(s),++q)s[q].$0()
s=m.c
r=s.a.d.sqlite3_close_v2(s.b)
n=r!==0?A.nL(m.b,s,r,"closing database",null,null):null
if(n!=null)throw A.a(n)}}
A.ij.prototype={
ex(){var s=this,r=s.d
return r==null?s.d=new A.bJ(s,A.n([],t.fS),new A.it(s),new A.iu(s),t.fs):r},
hD(){var s=this,r=s.e
return r==null?s.e=new A.bJ(s,A.n([],t.e),new A.iq(s),new A.ir(s),t.bq):r},
d_(){var s=this,r=s.f
return r==null?s.f=new A.bJ(s,A.n([],t.e),new A.il(s),new A.im(s),t.fK):r},
eG(a,b,c,d,e){var s,r,q,p,o,n=null,m=this.b,l=B.h.ac(e)
if(l.length>255)A.C(A.aD(e,"functionName","Must not exceed 255 bytes when utf-8 encoded"))
s=new Uint8Array(A.pK(l))
r=b?2049:1
if(c)r|=524288
q=m.a
p=q.b9(s,1)
s=q.d
o=A.hI(s,"dart_sqlite3_create_scalar_function",[m.b,p,a.a,r,q.c.iX(new A.fP(new A.iv(d),n,n))])
o=o
s.dart_sqlite3_free(p)
if(o!==0)A.eT(this,o,n,n,n)},
c8(a,b,c){return this.eG(a,!1,!0,b,c)},
an(){var s,r=this
if(r.r)return
$.hL().eJ(r)
r.r=!0
s=r.d
if(s!=null)s.q()
s=r.f
if(s!=null)s.q()
s=r.e
if(s!=null)s.q()
s=r.b
s.cP(null)
s.cN(null)
s.cO(null)
r.c.an()},
eL(a,b){var s,r,q,p=this
if(b.length===0){if(p.r)A.C(A.L("This database has already been closed"))
r=p.b
q=r.a
s=q.b9(B.h.ac(a),1)
q=q.d
r=A.hI(q,"sqlite3_exec",[r.b,s,0,0,0])
q.dart_sqlite3_free(s)
if(r!==0)A.eT(p,r,"executing",a,b)}else{s=p.eS(a,!0)
try{r=s
if(r.c.d)A.C(A.L(u.D))
r.bw()
r.e2(new A.fj(b))
r.fW()}finally{s.an()}}},
hq(a,b,c,a0,a1){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d=this
if(d.r)A.C(A.L("This database has already been closed"))
s=B.h.ac(a)
r=d.b
q=r.a
p=q.b8(s)
o=q.d
n=o.dart_sqlite3_malloc(4)
o=o.dart_sqlite3_malloc(4)
m=new A.k8(r,p,n,o)
l=A.n([],t.bb)
k=new A.io(m,l)
for(r=s.length,q=q.b,j=0;j<r;j=g){i=m.dU(j,r-j,0)
n=i.a
if(n!==0){k.$0()
A.eT(d,n,"preparing statement",a,null)}n=q.buffer
h=B.b.K(n.byteLength,4)
g=new Int32Array(n,0,h)[B.b.I(o,2)]-p
f=i.b
if(f!=null)l.push(new A.e1(f,d,new A.cJ(f),new A.eK(!1).d0(s,j,g,!0)))
if(l.length===c){j=g
break}}if(b)while(j<r){i=m.dU(j,r-j,0)
n=q.buffer
h=B.b.K(n.byteLength,4)
j=new Int32Array(n,0,h)[B.b.I(o,2)]-p
f=i.b
if(f!=null){l.push(new A.e1(f,d,new A.cJ(f),""))
k.$0()
throw A.a(A.aD(a,"sql","Had an unexpected trailing statement."))}else if(i.a!==0){k.$0()
throw A.a(A.aD(a,"sql","Has trailing data after the first sql statement:"))}}m.q()
for(r=l.length,q=d.c.d,e=0;e<l.length;l.length===r||(0,A.R)(l),++e)q.push(l[e].c)
return l},
eS(a,b){var s=this.hq(a,b,1,!1,!0)
if(s.length===0)throw A.a(A.aD(a,"sql","Must contain an SQL statement."))
return B.c.gaA(s)},
iV(a){return this.eS(a,!1)},
fh(a,b){var s,r=this.iV(a)
try{s=r
if(s.c.d)A.C(A.L(u.D))
s.bw()
s.e2(new A.fj(b))
s=s.hF()
return s}finally{r.an()}}}
A.it.prototype={
$0(){var s=this.a
s.b.cP(new A.is(s))},
$S:0}
A.is.prototype={
$3(a,b,c){var s=A.td(a)
if(s==null)return
this.a.d.ds(new A.aG(s,b,c))},
$S:65}
A.iu.prototype={
$0(){return this.a.b.cP(null)},
$S:0}
A.iq.prototype={
$0(){var s=this.a
return s.b.cO(new A.ip(s))},
$S:0}
A.ip.prototype={
$0(){this.a.e.ds(null)},
$S:0}
A.ir.prototype={
$0(){return this.a.b.cO(null)},
$S:0}
A.il.prototype={
$0(){var s=this.a
return s.b.cN(new A.ik(s))},
$S:0}
A.ik.prototype={
$0(){var s=this.a.f
s.ds(null)
return 0},
$S:66}
A.im.prototype={
$0(){return this.a.b.cN(null)},
$S:0}
A.iv.prototype={
$2(a,b){A.uo(a,this.a,b)},
$S:67}
A.io.prototype={
$0(){var s,r,q,p,o,n
this.a.q()
for(s=this.b,r=s.length,q=0;q<s.length;s.length===r||(0,A.R)(s),++q){p=s[q]
o=p.c
if(!o.d){n=$.hL().a
if(n!=null)n.unregister(p)
if(!o.d){o.d=!0
if(!o.c){n=o.b
n.c.d.sqlite3_reset(n.b)
o.c=!0}n=o.b
n.ca()
n.c.d.sqlite3_finalize(n.b)}n=p.b
if(!n.r)B.c.u(n.c.d,o)}}},
$S:0}
A.h5.prototype={
gk(a){return this.a.b},
j(a,b){var s,r,q=this.a
A.t2(b,this,"index",q.b)
s=this.b
r=s[b]
if(r==null){q=A.t4(q.j(0,b))
s[b]=q}else q=r
return q},
p(a,b,c){throw A.a(A.M("The argument list is unmodifiable",null))},
$ie_:1}
A.bJ.prototype={
gbo(){var s=this.f
return s==null?this.f=this.eb(!1):s},
eb(a){return new A.bh(!0,new A.m1(this,a),this.$ti.h("bh<1>"))},
ds(a){var s,r,q,p,o,n,m,l
for(s=this.b,r=s.length,q=0;q<s.length;s.length===r||(0,A.R)(s),++q){p=s[q]
o=p.a
if(p.b){n=o.b
if(n>=4)A.C(o.aI())
if((n&1)!==0){m=o.a;((n&8)!==0?m.gbA():m).b3(a)}}else{n=o.b
if(n>=4)A.C(o.aI())
if((n&1)!==0)o.aL(a)
else if((n&3)===0){o=o.bt()
n=new A.bI(a)
l=o.c
if(l==null)o.b=o.c=n
else{l.saS(n)
o.c=n}}}}},
q(){var s,r,q
for(s=this.b,r=s.length,q=0;q<s.length;s.length===r||(0,A.R)(s),++q)s[q].a.q()
this.c=null}}
A.m1.prototype={
$1(a){var s,r,q=this.a
if(q.a.r){a.q()
return}s=this.b
r=new A.m2(q,a,s)
a.r=a.e=new A.m3(q,a,s)
a.f=r
r.$0()},
$S(){return this.a.$ti.h("~(c0<1>)")}}
A.m2.prototype={
$0(){var s=this.a,r=s.b,q=r.length
r.push(new A.ew(this.b,this.c))
if(q===0)s.d.$0()},
$S:0}
A.m3.prototype={
$0(){var s=this.a,r=s.b
B.c.u(r,new A.ew(this.b,this.c))
r=r.length
if(r===0&&!s.a.r)s.e.$0()},
$S:0}
A.b7.prototype={}
A.my.prototype={
$1(a){a.an()},
$S:73}
A.jw.prototype={
iR(a,b){var s,r,q,p,o,n,m,l=null,k=this.a,j=k.b,i=j.fm()
if(i!==0)A.C(A.oQ(i,"Error returned by sqlite3_initialize",l,l,l,l,l))
switch(2){case 2:break}s=j.b9(B.h.ac(a),1)
r=j.d
q=r.dart_sqlite3_malloc(4)
p=j.b9(B.h.ac(b),1)
o=r.sqlite3_open_v2(s,q,6,p)
n=A.bw(j.b.buffer,0,l)[B.b.I(q,2)]
r.dart_sqlite3_free(s)
r.dart_sqlite3_free(p)
r.dart_sqlite3_free(p)
j=new A.k0(j,n)
if(o!==0){m=A.nL(k,j,o,"opening the database",l,l)
r.sqlite3_close_v2(n)
throw A.a(m)}r.sqlite3_extended_result_codes(n,1)
r=new A.ff(k,j,A.n([],t.eV),A.n([],t.bT))
j=new A.ij(k,j,r)
k=$.hL().a
if(k!=null)k.register(j,r,j)
return j}}
A.cJ.prototype={
an(){var s,r=this
if(!r.d){r.d=!0
r.bw()
s=r.b
s.ca()
s.c.d.sqlite3_finalize(s.b)}},
bw(){if(!this.c){var s=this.b
s.c.d.sqlite3_reset(s.b)
this.c=!0}}}
A.e1.prototype={
gfJ(){var s,r,q,p,o,n,m,l=this.a,k=l.c
l=l.b
s=k.d
r=s.sqlite3_column_count(l)
q=A.n([],t.s)
for(k=k.b,p=0;p<r;++p){o=s.sqlite3_column_name(l,p)
n=k.buffer
m=A.nn(k,o)
o=new Uint8Array(n,o,m)
q.push(new A.eK(!1).d0(o,0,null,!0))}return q},
ghL(){return null},
bw(){var s=this.c
s.bw()
s.b.ca()},
fW(){var s,r=this,q=r.c.c=!1,p=r.a,o=p.b
p=p.c.d
do s=p.sqlite3_step(o)
while(s===100)
if(s!==0?s!==101:q)A.eT(r.b,s,"executing statement",r.d,r.e)},
hF(){var s,r,q,p,o,n=this,m=A.n([],t.E),l=n.c.c=!1
for(s=n.a,r=s.b,s=s.c.d,q=-1;p=s.sqlite3_step(r),p===100;){if(q===-1)q=s.sqlite3_column_count(r)
p=[]
for(o=0;o<q;++o)p.push(n.hu(o))
m.push(p)}if(p!==0?p!==101:l)A.eT(n.b,p,"selecting from statement",n.d,n.e)
return A.oM(n.gfJ(),n.ghL(),m)},
hu(a){var s,r,q=this.a,p=q.c
q=q.b
s=p.d
switch(s.sqlite3_column_type(q,a)){case 1:q=s.sqlite3_column_int64(q,a)
return-9007199254740992<=q&&q<=9007199254740992?A.r(v.G.Number(q)):A.pa(q.toString(),null)
case 2:return s.sqlite3_column_double(q,a)
case 3:return A.bE(p.b,s.sqlite3_column_text(q,a),null)
case 4:r=s.sqlite3_column_bytes(q,a)
return A.p_(p.b,s.sqlite3_column_blob(q,a),r)
case 5:default:return null}},
fG(a){var s,r=a.length,q=r,p=this.a
p=p.c.d.sqlite3_bind_parameter_count(p.b)
if(q!==p)A.C(A.aD(a,"parameters","Expected "+A.y(p)+" parameters, got "+q))
if(r===0)return
for(s=1;s<=r;++s)this.fH(a[s-1],s)
this.e=a},
fH(a,b){var s,r,q,p,o,n=this
A:{if(a==null){s=n.a
s=s.c.d.sqlite3_bind_null(s.b,b)
break A}if(A.ct(a)){s=n.a
s=s.c.d.sqlite3_bind_int64(s.b,b,v.G.BigInt(a))
break A}if(a instanceof A.U){s=n.a
s=s.c.d.sqlite3_bind_int64(s.b,b,v.G.BigInt(A.o3(a).i(0)))
break A}if(A.dj(a)){s=n.a
r=a?1:0
s=s.c.d.sqlite3_bind_int64(s.b,b,v.G.BigInt(r))
break A}if(typeof a=="number"){s=n.a
s=s.c.d.sqlite3_bind_double(s.b,b,a)
break A}if(typeof a=="string"){s=n.a
q=B.h.ac(a)
p=s.c
o=p.b8(q)
s.d.push(o)
s=A.hI(p.d,"sqlite3_bind_text",[s.b,b,o,q.length,0])
break A}if(t.L.b(a)){s=n.a
p=s.c
o=p.b8(a)
s.d.push(o)
s=A.hI(p.d,"sqlite3_bind_blob64",[s.b,b,o,v.G.BigInt(J.aw(a)),0])
break A}s=n.fF(a,b)
break A}if(s!==0)A.eT(n.b,s,"binding parameter",n.d,n.e)},
fF(a,b){throw A.a(A.aD(a,"params["+b+"]","Allowed parameters must either be null or bool, int, num, String or List<int>."))},
e2(a){A:{this.fG(a.a)
break A}},
an(){var s,r=this.c
if(!r.d){$.hL().eJ(this)
r.an()
s=this.b
if(!s.r)B.c.u(s.c.d,r)}}}
A.fg.prototype={
bP(a,b){return this.d.N(a)?1:0},
cE(a,b){this.d.u(0,a)},
cF(a){return $.eX().cr("/"+a)},
aE(a,b){var s,r=a.a
if(r==null)r=A.n2(this.b,"/")
s=this.d
if(!s.N(r))if((b&4)!==0)s.p(0,r,new A.b1(new Uint8Array(0),0))
else throw A.a(A.bC(14))
return new A.cn(new A.hn(this,r,(b&8)!==0),0)},
cI(a){}}
A.hn.prototype={
dK(a,b){var s,r=this.a.d.j(0,this.b)
if(r==null||r.b<=b)return 0
s=Math.min(a.length,r.b-b)
B.d.H(a,0,s,J.cE(B.d.gaa(r.a),0,r.b),b)
return s},
cD(){return this.d>=2?1:0},
bQ(){if(this.c)this.a.d.u(0,this.b)},
bl(){return this.a.d.j(0,this.b).b},
cG(a){this.d=a},
cJ(a){},
bm(a){var s=this.a.d,r=this.b,q=s.j(0,r)
if(q==null){s.p(0,r,new A.b1(new Uint8Array(0),0))
s.j(0,r).sk(0,a)}else q.sk(0,a)},
cK(a){this.d=a},
aW(a,b){var s,r=this.a.d,q=this.b,p=r.j(0,q)
if(p==null){p=new A.b1(new Uint8Array(0),0)
r.p(0,q,p)}s=b+a.length
if(s>p.b)p.sk(0,s)
p.a8(0,b,s,a)}}
A.ig.prototype={
fI(){var s,r,q,p,o=A.a4(t.N,t.S)
for(s=this.a,r=s.length,q=0;q<s.length;s.length===r||(0,A.R)(s),++q){p=s[q]
o.p(0,p,B.c.dF(s,p))}this.c=o}}
A.fQ.prototype={
gt(a){return new A.lW(this)},
j(a,b){return new A.aY(this,A.j1(this.d[b],t.X))},
p(a,b,c){throw A.a(A.Y("Can't change rows from a result set"))},
gk(a){return this.d.length},
$ip:1,
$id:1,
$iu:1}
A.aY.prototype={
j(a,b){var s
if(typeof b!="string"){if(A.ct(b))return this.b[b]
return null}s=this.a.c.j(0,b)
if(s==null)return null
return this.b[s]},
ga_(){return this.a.a},
$iaf:1}
A.lW.prototype={
gm(){var s=this.a
return new A.aY(s,A.j1(s.d[this.b],t.X))},
l(){return++this.b<this.a.d.length}}
A.hy.prototype={}
A.hz.prototype={}
A.hA.prototype={}
A.hB.prototype={}
A.j9.prototype={
ae(){return"OpenMode."+this.b}}
A.i1.prototype={}
A.fj.prototype={}
A.aq.prototype={
i(a){return"VfsException("+this.a+")"},
$ia6:1}
A.dZ.prototype={}
A.bf.prototype={}
A.f4.prototype={}
A.f3.prototype={
gdS(){return 0},
cH(a,b){var s=this.dK(a,b),r=a.length
if(s<r){B.d.dt(a,s,r,0)
throw A.a(B.bv)}},
$id1:1}
A.k6.prototype={}
A.k0.prototype={
cP(a){var s,r=this.a
r.c.w=a
s=a!=null?1:-1
r=r.d.dart_sqlite3_updates
if(r!=null)r.call(null,this.b,s)},
cN(a){var s,r=this.a
r.c.x=a
s=a!=null?1:-1
r=r.d.dart_sqlite3_commits
if(r!=null)r.call(null,this.b,s)},
cO(a){var s,r=this.a
r.c.y=a
s=a!=null?1:-1
r=r.d.dart_sqlite3_rollbacks
if(r!=null)r.call(null,this.b,s)}}
A.k8.prototype={
q(){var s=this,r=s.a.a.d
r.dart_sqlite3_free(s.b)
r.dart_sqlite3_free(s.c)
r.dart_sqlite3_free(s.d)},
dU(a,b,c){var s,r=this,q=r.a,p=q.a,o=r.c
q=A.hI(p.d,"sqlite3_prepare_v3",[q.b,r.b+a,b,c,o,r.d])
s=A.bw(p.b.buffer,0,null)[B.b.I(o,2)]
return new A.fW(q,s===0?null:new A.k7(s,p,A.n([],t.t)))}}
A.k7.prototype={
ca(){var s,r,q,p
for(s=this.d,r=s.length,q=this.c.d,p=0;p<s.length;s.length===r||(0,A.R)(s),++p)q.dart_sqlite3_free(s[p])
B.c.aw(s)}}
A.bD.prototype={}
A.bg.prototype={}
A.d3.prototype={
j(a,b){var s=this.a
return new A.bg(s,A.bw(s.b.buffer,0,null)[B.b.I(this.c+b*4,2)])},
p(a,b,c){throw A.a(A.Y("Setting element in WasmValueList"))},
gk(a){return this.b}}
A.dv.prototype={
U(a,b,c,d){var s,r=null,q={},p=A.a9(A.fq(this.a,v.G.Symbol.asyncIterator,r,r,r,r)),o=A.jz(r,r,!0,this.$ti.c)
q.a=null
s=new A.hP(q,this,p,o)
o.d=s
o.f=new A.hQ(q,o,s)
return new A.as(o,A.D(o).h("as<1>")).U(a,b,c,d)},
be(a,b,c){return this.U(a,null,b,c)}}
A.hP.prototype={
$0(){var s,r=this,q=r.c.next(),p=r.a
p.a=q
s=r.d
A.Q(q,t.m).bi(new A.hR(p,r.b,s,r),s.gey(),t.P)},
$S:0}
A.hR.prototype={
$1(a){var s,r,q=this,p=a.done
if(p==null)p=null
s=a.value
r=q.c
if(p===!0){r.q()
q.a.a=null}else{r.E(0,s==null?q.b.$ti.c.a(s):s)
q.a.a=null
p=r.b
if(!((p&1)!==0?(r.gak().e&4)!==0:(p&2)===0))q.d.$0()}},
$S:15}
A.hQ.prototype={
$0(){var s,r
if(this.a.a==null){s=this.b
r=s.b
s=!((r&1)!==0?(s.gak().e&4)!==0:(r&2)===0)}else s=!1
if(s)this.c.$0()},
$S:0}
A.ch.prototype={
B(){var s=0,r=A.j(t.H),q=this,p
var $async$B=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:p=q.b
if(p!=null)p.B()
p=q.c
if(p!=null)p.B()
q.c=q.b=null
return A.h(null,r)}})
return A.i($async$B,r)},
gm(){var s=this.a
return s==null?A.C(A.L("Await moveNext() first")):s},
l(){var s,r,q,p=this,o=p.a
if(o!=null)o.continue()
o=new A.m($.q,t.k)
s=new A.H(o,t.fa)
r=p.d
q=t.m
p.b=A.ag(r,"success",new A.kH(p,s),!1,q)
p.c=A.ag(r,"error",new A.kI(p,s),!1,q)
return o}}
A.kH.prototype={
$1(a){var s,r=this.a
r.B()
s=r.$ti.h("1?").a(r.d.result)
r.a=s
this.b.O(s!=null)},
$S:1}
A.kI.prototype={
$1(a){var s=this.a
s.B()
s=s.d.error
if(s==null)s=a
this.b.a4(s)},
$S:1}
A.i4.prototype={
$1(a){this.a.O(this.c.a(this.b.result))},
$S:1}
A.i5.prototype={
$1(a){var s=this.b.error
if(s==null)s=a
this.a.a4(s)},
$S:1}
A.i9.prototype={
$1(a){this.a.O(this.c.a(this.b.result))},
$S:1}
A.ia.prototype={
$1(a){var s=this.b.error
if(s==null)s=a
this.a.a4(s)},
$S:1}
A.ib.prototype={
$1(a){var s=this.b.error
if(s==null)s=a
this.a.a4(s)},
$S:1}
A.iD.prototype={
$1(a){return A.a9(a[1])},
$S:52}
A.k3.prototype={
$2(a,b){var s={}
this.a[a]=s
b.Z(0,new A.k2(s))},
$S:36}
A.k2.prototype={
$2(a,b){this.a[a]=b},
$S:37}
A.d2.prototype={}
A.e7.prototype={
hE(a,b){var s,r,q=this.e
q.bk(b)
s=this.d.b
r=v.G
r.Atomics.store(s,1,-1)
r.Atomics.store(s,0,a.a)
A.r3(s,0)
r.Atomics.wait(s,1,-1)
s=r.Atomics.load(s,1)
if(s!==0)throw A.a(A.bC(s))
return a.d.$1(q)},
a1(a,b){var s=t.gR
return this.hE(a,b,s,s)},
bP(a,b){return this.a1(B.aq,new A.az(a,b,0,0)).a},
cE(a,b){this.a1(B.ar,new A.az(a,b,0,0))},
cF(a){var s=this.r.al(a)
if($.nY().hc("/",s)!==B.J)throw A.a(B.ao)
return s},
aE(a,b){var s=a.a,r=this.a1(B.aC,new A.az(s==null?A.n2(this.b,"/"):s,b,0,0))
return new A.cn(new A.h8(this,r.b),r.a)},
cI(a){this.a1(B.aw,new A.J(B.b.K(a.a,1000),0,0))},
q(){this.a1(B.as,B.f)}}
A.h8.prototype={
gdS(){return 2048},
dK(a,b){var s,r,q,p,o,n,m,l,k,j,i=a.length
for(s=this.a,r=this.b,q=s.e.a,p=v.G,o=t.Z,n=0;i>0;){m=Math.min(65536,i)
i-=m
l=s.a1(B.aA,new A.J(r,b+n,m)).a
k=p.Uint8Array
j=[q]
j.push(0)
j.push(l)
A.fq(a,"set",o.a(A.cw(k,j)),n,null,null)
n+=l
if(l<m)break}return n},
cD(){return this.c!==0?1:0},
bQ(){this.a.a1(B.ax,new A.J(this.b,0,0))},
bl(){return this.a.a1(B.aB,new A.J(this.b,0,0)).a},
cG(a){var s=this
if(s.c===0)s.a.a1(B.at,new A.J(s.b,a,0))
s.c=a},
cJ(a){this.a.a1(B.ay,new A.J(this.b,0,0))},
bm(a){this.a.a1(B.az,new A.J(this.b,a,0))},
cK(a){if(this.c!==0&&a===0)this.a.a1(B.au,new A.J(this.b,a,0))},
aW(a,b){var s,r,q,p,o,n=a.length
for(s=this.a,r=s.e.c,q=this.b,p=0;n>0;){o=Math.min(65536,n)
A.fq(r,"set",o===n&&p===0?a:J.cE(B.d.gaa(a),a.byteOffset+p,o),0,null,null)
s.a1(B.av,new A.J(q,b+p,o))
p+=o
n-=o}}}
A.jn.prototype={}
A.aW.prototype={
bk(a){var s,r
if(!(a instanceof A.aE))if(a instanceof A.J){s=this.b
s.$flags&2&&A.v(s,8)
s.setInt32(0,a.a,!1)
s.setInt32(4,a.b,!1)
s.setInt32(8,a.c,!1)
if(a instanceof A.az){r=B.h.ac(a.d)
s.setInt32(12,r.length,!1)
B.d.aF(this.c,16,r)}}else throw A.a(A.Y("Message "+a.i(0)))}}
A.Z.prototype={
ae(){return"WorkerOperation."+this.b}}
A.bb.prototype={}
A.aE.prototype={}
A.J.prototype={}
A.az.prototype={}
A.hx.prototype={}
A.e6.prototype={
bx(a,b){return this.hB(a,b)},
el(a){return this.bx(a,!1)},
hB(a,b){var s=0,r=A.j(t.eg),q,p=this,o,n,m,l,k,j,i,h,g
var $async$bx=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:j=$.eX()
i=j.eU(a,"/")
h=j.cM(0,i)
g=h.length
j=g>=1
o=null
if(j){n=g-1
m=B.c.cR(h,0,n)
o=h[n]}else m=null
if(!j)throw A.a(A.L("Pattern matching error"))
l=p.c
j=m.length,n=t.m,k=0
case 3:if(!(k<m.length)){s=5
break}s=6
return A.c(A.Q(l.getDirectoryHandle(m[k],{create:b}),n),$async$bx)
case 6:l=d
case 4:m.length===j||(0,A.R)(m),++k
s=3
break
case 5:q=new A.hx(i,l,o)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$bx,r)},
bB(a){return this.hP(a)},
hP(a){var s=0,r=A.j(t.f),q,p=2,o=[],n=this,m,l,k,j
var $async$bB=A.k(function(b,c){if(b===1){o.push(c)
s=p}for(;;)switch(s){case 0:p=4
s=7
return A.c(n.el(a.d),$async$bB)
case 7:m=c
l=m
s=8
return A.c(A.Q(l.b.getFileHandle(l.c,{create:!1}),t.m),$async$bB)
case 8:q=new A.J(1,0,0)
s=1
break
p=2
s=6
break
case 4:p=3
j=o.pop()
q=new A.J(0,0,0)
s=1
break
s=6
break
case 3:s=2
break
case 6:case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$bB,r)},
bC(a){return this.hR(a)},
hR(a){var s=0,r=A.j(t.H),q=1,p=[],o=this,n,m,l,k
var $async$bC=A.k(function(b,c){if(b===1){p.push(c)
s=q}for(;;)switch(s){case 0:s=2
return A.c(o.el(a.d),$async$bC)
case 2:l=c
q=4
s=7
return A.c(A.mY(l.b,l.c),$async$bC)
case 7:q=1
s=6
break
case 4:q=3
k=p.pop()
n=A.W(k)
A.y(n)
throw A.a(B.bt)
s=6
break
case 3:s=1
break
case 6:return A.h(null,r)
case 1:return A.f(p.at(-1),r)}})
return A.i($async$bC,r)},
bD(a){return this.hU(a)},
hU(a){var s=0,r=A.j(t.f),q,p=2,o=[],n=this,m,l,k,j,i,h,g,f,e
var $async$bD=A.k(function(b,c){if(b===1){o.push(c)
s=p}for(;;)switch(s){case 0:h=a.a
g=(h&4)!==0
f=null
p=4
s=7
return A.c(n.bx(a.d,g),$async$bD)
case 7:f=c
p=2
s=6
break
case 4:p=3
e=o.pop()
l=A.bC(12)
throw A.a(l)
s=6
break
case 3:s=2
break
case 6:l=f
s=8
return A.c(A.Q(l.b.getFileHandle(l.c,{create:g}),t.m),$async$bD)
case 8:k=c
j=!g&&(h&1)!==0
l=n.d++
i=f.b
n.f.p(0,l,new A.dd(l,j,(h&8)!==0,f.a,i,f.c,k))
q=new A.J(j?1:0,l,0)
s=1
break
case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$bD,r)},
c2(a){return this.hV(a)},
hV(a){var s=0,r=A.j(t.f),q,p=this,o,n,m
var $async$c2=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:o=p.f.j(0,a.a)
o.toString
n=A
m=A
s=3
return A.c(p.au(o),$async$c2)
case 3:q=new n.J(m.iE(c,A.nd(p.b.a,0,a.c),{at:a.b}),0,0)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$c2,r)},
c4(a){return this.hZ(a)},
hZ(a){var s=0,r=A.j(t.r),q,p=this,o,n,m
var $async$c4=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:n=p.f.j(0,a.a)
n.toString
o=a.c
m=A
s=3
return A.c(p.au(n),$async$c4)
case 3:if(m.mZ(c,A.nd(p.b.a,0,o),{at:a.b})!==o)throw A.a(B.ap)
q=B.f
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$c4,r)},
c_(a){return this.hQ(a)},
hQ(a){var s=0,r=A.j(t.H),q=this,p
var $async$c_=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:p=q.f.u(0,a.a)
q.r.u(0,p)
if(p==null)throw A.a(B.bs)
q.cY(p)
s=p.c?2:3
break
case 2:s=4
return A.c(A.mY(p.e,p.f),$async$c_)
case 4:case 3:return A.h(null,r)}})
return A.i($async$c_,r)},
c0(a){return this.hS(a)},
hS(a){var s=0,r=A.j(t.f),q,p=2,o=[],n=[],m=this,l,k,j,i
var $async$c0=A.k(function(b,c){if(b===1){o.push(c)
s=p}for(;;)switch(s){case 0:i=m.f.j(0,a.a)
i.toString
l=i
p=3
s=6
return A.c(m.au(l),$async$c0)
case 6:k=c
j=k.getSize()
q=new A.J(j,0,0)
n=[1]
s=4
break
n.push(5)
s=4
break
case 3:n=[2]
case 4:p=2
i=l
if(m.r.u(0,i))m.cZ(i)
s=n.pop()
break
case 5:case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$c0,r)},
c3(a){return this.hX(a)},
hX(a){var s=0,r=A.j(t.r),q,p=2,o=[],n=[],m=this,l,k,j
var $async$c3=A.k(function(b,c){if(b===1){o.push(c)
s=p}for(;;)switch(s){case 0:j=m.f.j(0,a.a)
j.toString
l=j
if(l.b)A.C(B.bw)
p=3
s=6
return A.c(m.au(l),$async$c3)
case 6:k=c
k.truncate(a.b)
n.push(5)
s=4
break
case 3:n=[2]
case 4:p=2
j=l
if(m.r.u(0,j))m.cZ(j)
s=n.pop()
break
case 5:q=B.f
s=1
break
case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$c3,r)},
dm(a){return this.hW(a)},
hW(a){var s=0,r=A.j(t.r),q,p=this,o,n
var $async$dm=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:o=p.f.j(0,a.a)
n=o.x
if(!o.b&&n!=null)n.flush()
q=B.f
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$dm,r)},
c1(a){return this.hT(a)},
hT(a){var s=0,r=A.j(t.r),q,p=2,o=[],n=this,m,l,k,j
var $async$c1=A.k(function(b,c){if(b===1){o.push(c)
s=p}for(;;)switch(s){case 0:k=n.f.j(0,a.a)
k.toString
m=k
s=m.x==null?3:5
break
case 3:p=7
s=10
return A.c(n.au(m),$async$c1)
case 10:m.w=!0
p=2
s=9
break
case 7:p=6
j=o.pop()
throw A.a(B.bu)
s=9
break
case 6:s=2
break
case 9:s=4
break
case 5:m.w=!0
case 4:q=B.f
s=1
break
case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$c1,r)},
dn(a){return this.hY(a)},
hY(a){var s=0,r=A.j(t.r),q,p=this,o
var $async$dn=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:o=p.f.j(0,a.a)
if(o.x!=null&&a.b===0)p.cY(o)
q=B.f
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$dn,r)},
V(){var s=0,r=A.j(t.H),q=1,p=[],o=this,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3
var $async$V=A.k(function(a4,a5){if(a4===1){p.push(a5)
s=q}for(;;)switch(s){case 0:h=o.a.b,g=v.G,f=o.b,e=o.ghx(),d=o.r,c=d.$ti.c,b=t.f,a=t.eN,a0=t.H
case 2:if(!!o.e){s=3
break}if(g.Atomics.wait(h,0,-1,150)==="timed-out"){a1=A.b9(d,c)
B.c.Z(a1,e)
s=2
break}n=null
m=null
l=null
q=5
a1=g.Atomics.load(h,0)
g.Atomics.store(h,0,-1)
m=B.b9[a1]
l=m.c.$1(f)
k=null
case 8:switch(m.a){case 5:s=10
break
case 0:s=11
break
case 1:s=12
break
case 2:s=13
break
case 3:s=14
break
case 4:s=15
break
case 6:s=16
break
case 7:s=17
break
case 9:s=18
break
case 8:s=19
break
case 10:s=20
break
case 11:s=21
break
case 12:s=22
break
default:s=9
break}break
case 10:a1=A.b9(d,c)
B.c.Z(a1,e)
s=23
return A.c(A.rx(A.oh(0,b.a(l).a),a0),$async$V)
case 23:k=B.f
s=9
break
case 11:s=24
return A.c(o.bB(a.a(l)),$async$V)
case 24:k=a5
s=9
break
case 12:s=25
return A.c(o.bC(a.a(l)),$async$V)
case 25:k=B.f
s=9
break
case 13:s=26
return A.c(o.bD(a.a(l)),$async$V)
case 26:k=a5
s=9
break
case 14:s=27
return A.c(o.c2(b.a(l)),$async$V)
case 27:k=a5
s=9
break
case 15:s=28
return A.c(o.c4(b.a(l)),$async$V)
case 28:k=a5
s=9
break
case 16:s=29
return A.c(o.c_(b.a(l)),$async$V)
case 29:k=B.f
s=9
break
case 17:s=30
return A.c(o.c0(b.a(l)),$async$V)
case 30:k=a5
s=9
break
case 18:s=31
return A.c(o.c3(b.a(l)),$async$V)
case 31:k=a5
s=9
break
case 19:s=32
return A.c(o.dm(b.a(l)),$async$V)
case 32:k=a5
s=9
break
case 20:s=33
return A.c(o.c1(b.a(l)),$async$V)
case 33:k=a5
s=9
break
case 21:s=34
return A.c(o.dn(b.a(l)),$async$V)
case 34:k=a5
s=9
break
case 22:k=B.f
o.e=!0
a1=A.b9(d,c)
B.c.Z(a1,e)
s=9
break
case 9:f.bk(k)
n=0
q=1
s=7
break
case 5:q=4
a3=p.pop()
a1=A.W(a3)
if(a1 instanceof A.aq){j=a1
A.y(j)
A.y(m)
A.y(l)
n=j.a}else{i=a1
A.y(i)
A.y(m)
A.y(l)
n=1}s=7
break
case 4:s=1
break
case 7:a1=n
g.Atomics.store(h,1,a1)
g.Atomics.notify(h,1,1/0)
s=2
break
case 3:return A.h(null,r)
case 1:return A.f(p.at(-1),r)}})
return A.i($async$V,r)},
hy(a){if(this.r.u(0,a))this.cZ(a)},
au(a){return this.ho(a)},
ho(a){var s=0,r=A.j(t.m),q,p=2,o=[],n=this,m,l,k,j,i,h,g,f,e,d
var $async$au=A.k(function(b,c){if(b===1){o.push(c)
s=p}for(;;)switch(s){case 0:e=a.x
if(e!=null){q=e
s=1
break}m=1
k=a.r,j=t.m,i=n.r
case 3:p=6
s=9
return A.c(A.Q(k.createSyncAccessHandle(),j),$async$au)
case 9:h=c
a.x=h
l=h
if(!a.w)i.E(0,a)
g=l
q=g
s=1
break
p=2
s=8
break
case 6:p=5
d=o.pop()
if(J.a_(m,6))throw A.a(B.br)
A.y(m);++m
s=8
break
case 5:s=2
break
case 8:s=3
break
case 4:case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$au,r)},
cZ(a){var s
try{this.cY(a)}catch(s){}},
cY(a){var s=a.x
if(s!=null){a.x=null
this.r.u(0,a)
a.w=!1
s.close()}}}
A.dd.prototype={}
A.f1.prototype={
de(a,b,c){var s=t.B
return v.G.IDBKeyRange.bound(A.n([a,c],s),A.n([a,b],s))},
hs(a){return this.de(a,9007199254740992,0)},
ht(a,b){return this.de(a,9007199254740992,b)},
cs(){var s=0,r=A.j(t.H),q=this,p,o
var $async$cs=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:p=new A.m($.q,t.et)
o=v.G.indexedDB.open(q.b,1)
o.onupgradeneeded=A.aK(new A.hX(o))
new A.H(p,t.eC).O(A.rf(o,t.m))
s=2
return A.c(p,$async$cs)
case 2:q.a=b
return A.h(null,r)}})
return A.i($async$cs,r)},
q(){var s=this.a
if(s!=null)s.close()},
cq(){var s=0,r=A.j(t.g6),q,p=this,o,n,m,l,k
var $async$cq=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:l=A.a4(t.N,t.S)
k=new A.ch(p.a.transaction("files","readonly").objectStore("files").index("fileName").openKeyCursor(),t.Q)
case 3:s=5
return A.c(k.l(),$async$cq)
case 5:if(!b){s=4
break}o=k.a
if(o==null)o=A.C(A.L("Await moveNext() first"))
n=o.key
n.toString
A.ah(n)
m=o.primaryKey
m.toString
l.p(0,n,A.r(A.z(m)))
s=3
break
case 4:q=l
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$cq,r)},
cd(a){return this.ih(a)},
ih(a){var s=0,r=A.j(t.I),q,p=this,o
var $async$cd=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:o=A
s=3
return A.c(A.aT(p.a.transaction("files","readonly").objectStore("files").index("fileName").getKey(a),t.i),$async$cd)
case 3:q=o.r(c)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$cd,r)},
c7(a){return this.i8(a)},
i8(a){var s=0,r=A.j(t.S),q,p=this,o
var $async$c7=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:o=A
s=3
return A.c(A.aT(p.a.transaction("files","readwrite").objectStore("files").put({name:a,length:0}),t.i),$async$c7)
case 3:q=o.r(c)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$c7,r)},
df(a,b){return A.aT(a.objectStore("files").get(b),t.A).dO(new A.hU(b),t.m)},
bg(a){return this.iW(a)},
iW(a){var s=0,r=A.j(t.p),q,p=this,o,n,m,l,k,j,i,h,g,f,e
var $async$bg=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:e=p.a
e.toString
o=e.transaction($.mQ(),"readonly")
n=o.objectStore("blocks")
s=3
return A.c(p.df(o,a),$async$bg)
case 3:m=c
e=m.length
l=new Uint8Array(e)
k=A.n([],t.M)
j=new A.ch(n.openCursor(p.hs(a)),t.Q)
e=t.H,i=t.c
case 4:s=6
return A.c(j.l(),$async$bg)
case 6:if(!c){s=5
break}h=j.a
if(h==null)h=A.C(A.L("Await moveNext() first"))
g=i.a(h.key)
f=A.r(A.z(g[1]))
k.push(A.dH(new A.hY(h,l,f,Math.min(4096,m.length-f)),e))
s=4
break
case 5:s=7
return A.c(A.n1(k,e),$async$bg)
case 7:q=l
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$bg,r)},
aM(a,b){return this.hN(a,b)},
hN(a,b){var s=0,r=A.j(t.H),q=this,p,o,n,m,l,k,j
var $async$aM=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:j=q.a
j.toString
p=j.transaction($.mQ(),"readwrite")
o=p.objectStore("blocks")
s=2
return A.c(q.df(p,a),$async$aM)
case 2:n=d
j=b.b
m=A.D(j).h("b8<1>")
l=A.b9(new A.b8(j,m),m.h("d.E"))
B.c.fk(l)
s=3
return A.c(A.n1(new A.aa(l,new A.hV(new A.hW(o,a),b),A.ac(l).h("aa<1,K<~>>")),t.H),$async$aM)
case 3:s=b.c!==n.length?4:5
break
case 4:k=new A.ch(p.objectStore("files").openCursor(a),t.Q)
s=6
return A.c(k.l(),$async$aM)
case 6:s=7
return A.c(A.aT(k.gm().update({name:n.name,length:b.c}),t.X),$async$aM)
case 7:case 5:return A.h(null,r)}})
return A.i($async$aM,r)},
aV(a,b,c){return this.j9(0,b,c)},
j9(a,b,c){var s=0,r=A.j(t.H),q=this,p,o,n,m,l,k
var $async$aV=A.k(function(d,e){if(d===1)return A.f(e,r)
for(;;)switch(s){case 0:k=q.a
k.toString
p=k.transaction($.mQ(),"readwrite")
o=p.objectStore("files")
n=p.objectStore("blocks")
s=2
return A.c(q.df(p,b),$async$aV)
case 2:m=e
s=m.length>c?3:4
break
case 3:s=5
return A.c(A.aT(n.delete(q.ht(b,B.b.K(c,4096)*4096+1)),t.X),$async$aV)
case 5:case 4:l=new A.ch(o.openCursor(b),t.Q)
s=6
return A.c(l.l(),$async$aV)
case 6:s=7
return A.c(A.aT(l.gm().update({name:m.name,length:c}),t.X),$async$aV)
case 7:return A.h(null,r)}})
return A.i($async$aV,r)},
cc(a){return this.ib(a)},
ib(a){var s=0,r=A.j(t.H),q=this,p,o,n
var $async$cc=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:n=q.a
n.toString
p=n.transaction(A.n(["files","blocks"],t.s),"readwrite")
o=q.de(a,9007199254740992,0)
n=t.X
s=2
return A.c(A.n1(A.n([A.aT(p.objectStore("blocks").delete(o),n),A.aT(p.objectStore("files").delete(a),n)],t.M),t.H),$async$cc)
case 2:return A.h(null,r)}})
return A.i($async$cc,r)}}
A.hX.prototype={
$1(a){var s=A.a9(this.a.result)
if(J.a_(a.oldVersion,0)){s.createObjectStore("files",{autoIncrement:!0}).createIndex("fileName","name",{unique:!0})
s.createObjectStore("blocks")}},
$S:15}
A.hU.prototype={
$1(a){if(a==null)throw A.a(A.aD(this.a,"fileId","File not found in database"))
else return a},
$S:39}
A.hY.prototype={
$0(){var s=0,r=A.j(t.H),q=this,p,o
var $async$$0=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:p=q.a
s=A.oo(p.value,"Blob")?2:4
break
case 2:s=5
return A.c(A.jk(A.a9(p.value)),$async$$0)
case 5:s=3
break
case 4:b=t.a.a(p.value)
case 3:o=b
B.d.aF(q.b,q.c,J.cE(o,0,q.d))
return A.h(null,r)}})
return A.i($async$$0,r)},
$S:2}
A.hW.prototype={
fd(a,b){var s=0,r=A.j(t.H),q=this,p,o,n,m,l,k
var $async$$2=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:p=q.a
o=q.b
n=t.B
s=2
return A.c(A.aT(p.openCursor(v.G.IDBKeyRange.only(A.n([o,a],n))),t.A),$async$$2)
case 2:m=d
l=t.a.a(B.d.gaa(b))
k=t.X
s=m==null?3:5
break
case 3:s=6
return A.c(A.aT(p.put(l,A.n([o,a],n)),k),$async$$2)
case 6:s=4
break
case 5:s=7
return A.c(A.aT(m.update(l),k),$async$$2)
case 7:case 4:return A.h(null,r)}})
return A.i($async$$2,r)},
$2(a,b){return this.fd(a,b)},
$S:40}
A.hV.prototype={
$1(a){var s=this.b.b.j(0,a)
s.toString
return this.a.$2(a,s)},
$S:41}
A.kN.prototype={
hM(a,b,c){B.d.aF(this.b.eT(a,new A.kO(this,a)),b,c)},
i4(a,b){var s,r,q,p,o,n,m,l
for(s=b.length,r=0;r<s;r=l){q=a+r
p=B.b.K(q,4096)
o=B.b.a7(q,4096)
n=s-r
if(o!==0)m=Math.min(4096-o,n)
else{m=Math.min(4096,n)
o=0}l=r+m
this.hM(p*4096,o,J.cE(B.d.gaa(b),b.byteOffset+r,m))}this.c=Math.max(this.c,a+s)}}
A.kO.prototype={
$0(){var s=new Uint8Array(4096),r=this.a.a,q=r.length,p=this.b
if(q>p)B.d.aF(s,0,J.cE(B.d.gaa(r),r.byteOffset+p,Math.min(4096,q-p)))
return s},
$S:42}
A.hv.prototype={}
A.bY.prototype={
b7(a){var s=this
if(s.e||s.d.a==null)A.C(A.bC(10))
if(a.dC(s.w)){s.eo()
return a.d.a}else return A.n0(null,t.H)},
eo(){var s,r,q=this
if(q.f==null&&!q.w.gv(0)){s=q.w
r=q.f=s.gaA(0)
s.u(0,r)
r.d.O(A.oj(r.gcz(),t.H).W(new A.iR(q)))}},
q(){var s=0,r=A.j(t.H),q,p=this,o,n
var $async$q=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:if(!p.e){o=p.b7(new A.cj(p.d.gaz(),new A.H(new A.m($.q,t.D),t.F)))
p.e=!0
q=o
s=1
break}else{n=p.w
if(!n.gv(0)){q=n.gap(0).d.a
s=1
break}}case 1:return A.h(q,r)}})
return A.i($async$q,r)},
b4(a){return this.fY(a)},
fY(a){var s=0,r=A.j(t.S),q,p=this,o,n
var $async$b4=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:n=p.y
s=n.N(a)?3:5
break
case 3:n=n.j(0,a)
n.toString
q=n
s=1
break
s=4
break
case 5:s=6
return A.c(p.d.cd(a),$async$b4)
case 6:o=c
o.toString
n.p(0,a,o)
q=o
s=1
break
case 4:case 1:return A.h(q,r)}})
return A.i($async$b4,r)},
bu(){var s=0,r=A.j(t.H),q=this,p,o,n,m,l,k,j,i,h,g
var $async$bu=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:h=q.d
s=2
return A.c(h.cq(),$async$bu)
case 2:g=b
q.y.am(0,g)
p=g.gbF(),p=p.gt(p),o=q.r.d
case 3:if(!p.l()){s=4
break}n=p.gm()
m=n.a
l=n.b
k=new A.b1(new Uint8Array(0),0)
s=5
return A.c(h.bg(l),$async$bu)
case 5:j=b
n=j.length
k.sk(0,n)
i=k.b
if(n>i)A.C(A.S(n,0,i,null,null))
B.d.H(k.a,0,n,j,0)
o.p(0,m,k)
s=3
break
case 4:return A.h(null,r)}})
return A.i($async$bu,r)},
il(){return this.b7(new A.cj(new A.iS(),new A.H(new A.m($.q,t.D),t.F)))},
bP(a,b){return this.r.d.N(a)?1:0},
cE(a,b){var s=this
s.r.d.u(0,a)
if(!s.x.u(0,a))s.b7(new A.d8(s,a,new A.H(new A.m($.q,t.D),t.F)))},
cF(a){return $.eX().cr("/"+a)},
aE(a,b){var s,r,q,p=this,o=a.a
if(o==null)o=A.n2(p.b,"/")
s=p.r
r=s.d.N(o)?1:0
q=s.aE(new A.dZ(o),b)
if(r===0)if((b&8)!==0)p.x.E(0,o)
else p.b7(new A.cg(p,o,new A.H(new A.m($.q,t.D),t.F)))
return new A.cn(new A.ho(p,q.a,o),0)},
cI(a){}}
A.iR.prototype={
$0(){var s=this.a
s.f=null
s.eo()},
$S:4}
A.iS.prototype={
$0(){},
$S:4}
A.ho.prototype={
cH(a,b){this.b.cH(a,b)},
gdS(){return 0},
cD(){return this.b.d>=2?1:0},
bQ(){},
bl(){return this.b.bl()},
cG(a){this.b.d=a
return null},
cJ(a){},
bm(a){var s=this,r=s.a
if(r.e||r.d.a==null)A.C(A.bC(10))
s.b.bm(a)
if(!r.x.a5(0,s.c))r.b7(new A.cj(new A.l0(s,a),new A.H(new A.m($.q,t.D),t.F)))},
cK(a){this.b.d=a
return null},
aW(a,b){var s,r,q,p,o,n,m=this,l=m.a
if(l.e||l.d.a==null)A.C(A.bC(10))
s=m.c
if(l.x.a5(0,s)){m.b.aW(a,b)
return}r=l.r.d.j(0,s)
if(r==null)r=new A.b1(new Uint8Array(0),0)
q=J.cE(B.d.gaa(r.a),0,r.b)
m.b.aW(a,b)
p=new Uint8Array(a.length)
B.d.aF(p,0,a)
o=A.n([],t.f6)
n=$.q
o.push(new A.hv(b,p))
l.b7(new A.cs(l,s,q,o,new A.H(new A.m(n,t.D),t.F)))},
$id1:1}
A.l0.prototype={
$0(){var s=0,r=A.j(t.H),q,p=this,o,n,m
var $async$$0=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:o=p.a
n=o.a
m=n.d
s=3
return A.c(n.b4(o.c),$async$$0)
case 3:q=m.aV(0,b,p.b)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$$0,r)},
$S:2}
A.a8.prototype={
dC(a){a.d5(a.c,this,!1)
return!0}}
A.cj.prototype={
R(){return this.w.$0()}}
A.d8.prototype={
dC(a){var s,r,q,p
if(!a.gv(0)){s=a.gap(0)
for(r=this.x;s!=null;)if(s instanceof A.d8)if(s.x===r)return!1
else s=s.gbM()
else if(s instanceof A.cs){q=s.gbM()
if(s.x===r){p=s.a
p.toString
p.dj(A.D(s).h("am.E").a(s))}s=q}else if(s instanceof A.cg){if(s.x===r){r=s.a
r.toString
r.dj(A.D(s).h("am.E").a(s))
return!1}s=s.gbM()}else break}a.d5(a.c,this,!1)
return!0},
R(){var s=0,r=A.j(t.H),q=this,p,o,n
var $async$R=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:p=q.w
o=q.x
s=2
return A.c(p.b4(o),$async$R)
case 2:n=b
p.y.u(0,o)
s=3
return A.c(p.d.cc(n),$async$R)
case 3:return A.h(null,r)}})
return A.i($async$R,r)}}
A.cg.prototype={
R(){var s=0,r=A.j(t.H),q=this,p,o,n,m
var $async$R=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:p=q.w
o=q.x
n=p.y
m=o
s=2
return A.c(p.d.c7(o),$async$R)
case 2:n.p(0,m,b)
return A.h(null,r)}})
return A.i($async$R,r)}}
A.cs.prototype={
dC(a){var s,r=a.b===0?null:a.gap(0)
for(s=this.x;r!=null;)if(r instanceof A.cs)if(r.x===s){B.c.am(r.z,this.z)
return!1}else r=r.gbM()
else if(r instanceof A.cg){if(r.x===s)break
r=r.gbM()}else break
a.d5(a.c,this,!1)
return!0},
R(){var s=0,r=A.j(t.H),q=this,p,o,n,m,l,k
var $async$R=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:m=q.y
l=new A.kN(m,A.a4(t.S,t.p),m.length)
for(m=q.z,p=m.length,o=0;o<m.length;m.length===p||(0,A.R)(m),++o){n=m[o]
l.i4(n.a,n.b)}m=q.w
k=m.d
s=3
return A.c(m.b4(q.x),$async$R)
case 3:s=2
return A.c(k.aM(b,l),$async$R)
case 2:return A.h(null,r)}})
return A.i($async$R,r)}}
A.cI.prototype={
ae(){return"FileType."+this.b}}
A.cY.prototype={
d6(a,b){var s=this.e,r=b?1:0
s.$flags&2&&A.v(s)
s[a.a]=r
A.mZ(this.d,s,{at:0})},
bP(a,b){var s,r=$.mR().j(0,a)
if(r==null)return this.r.d.N(a)?1:0
else{s=this.e
A.iE(this.d,s,{at:0})
return s[r.a]}},
cE(a,b){var s=$.mR().j(0,a)
if(s==null){this.r.d.u(0,a)
return null}else this.d6(s,!1)},
cF(a){return $.eX().cr("/"+a)},
aE(a,b){var s,r,q,p=this,o=a.a
if(o==null)return p.r.aE(a,b)
s=$.mR().j(0,o)
if(s==null)return p.r.aE(a,b)
r=p.e
A.iE(p.d,r,{at:0})
r=r[s.a]
q=p.f.j(0,s)
q.toString
if(r===0)if((b&4)!==0){q.truncate(0)
p.d6(s,!0)}else throw A.a(B.ao)
return new A.cn(new A.hC(p,s,q,(b&8)!==0),0)},
cI(a){},
q(){this.d.close()
for(var s=this.f,s=new A.cM(s,s.r,s.e);s.l();)s.d.close()}}
A.jv.prototype={
fe(a){var s=0,r=A.j(t.m),q,p=this,o,n
var $async$$1=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:o=t.m
s=3
return A.c(A.Q(p.a.getFileHandle(a,{create:!0}),o),$async$$1)
case 3:n=c
s=4
return A.c(A.Q(p.b?n.createSyncAccessHandle({mode:"readwrite-unsafe"}):n.createSyncAccessHandle(),o),$async$$1)
case 4:q=c
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$$1,r)},
$1(a){return this.fe(a)},
$S:43}
A.hC.prototype={
dK(a,b){return A.iE(this.c,a,{at:b})},
cD(){return this.e>=2?1:0},
bQ(){var s=this
s.c.flush()
if(s.d)s.a.d6(s.b,!1)},
bl(){return this.c.getSize()},
cG(a){this.e=a},
cJ(a){this.c.flush()},
bm(a){this.c.truncate(a)},
cK(a){this.e=a},
aW(a,b){if(A.mZ(this.c,a,{at:b})<a.length)throw A.a(B.ap)}}
A.h7.prototype={
b9(a,b){var s=J.au(a),r=this.d.dart_sqlite3_malloc(s.gk(a)+b),q=A.aF(this.b.buffer,0,null)
B.d.a8(q,r,r+s.gk(a),a)
B.d.dt(q,r+s.gk(a),r+s.gk(a)+b,0)
return r},
b8(a){return this.b9(a,0)},
fm(){var s,r=this.d.sqlite3_initialize
A:{if(r!=null){s=A.r(A.z(r.call(null)))
break A}s=0
break A}return s}}
A.l1.prototype={
fA(){var s=this,r=s.c=new v.G.WebAssembly.Memory({initial:16}),q=t.N,p=t.m
s.b=A.n6(["env",A.n6(["memory",r],q,p),"dart",A.n6(["error_log",A.aK(new A.lh(r)),"xOpen",A.nF(new A.li(s,r)),"xDelete",A.eN(new A.lj(s,r)),"xAccess",A.mo(new A.lu(s,r)),"xFullPathname",A.mo(new A.lF(s,r)),"xRandomness",A.eN(new A.lG(s,r)),"xSleep",A.b4(new A.lH(s)),"xCurrentTimeInt64",A.b4(new A.lI(s,r)),"xDeviceCharacteristics",A.aK(new A.lJ(s)),"xClose",A.aK(new A.lK(s)),"xRead",A.mo(new A.lL(s,r)),"xWrite",A.mo(new A.lk(s,r)),"xTruncate",A.b4(new A.ll(s)),"xSync",A.b4(new A.lm(s)),"xFileSize",A.b4(new A.ln(s,r)),"xLock",A.b4(new A.lo(s)),"xUnlock",A.b4(new A.lp(s)),"xCheckReservedLock",A.b4(new A.lq(s,r)),"function_xFunc",A.eN(new A.lr(s)),"function_xStep",A.eN(new A.ls(s)),"function_xInverse",A.eN(new A.lt(s)),"function_xFinal",A.aK(new A.lv(s)),"function_xValue",A.aK(new A.lw(s)),"function_forget",A.aK(new A.lx(s)),"function_compare",A.nF(new A.ly(s,r)),"function_hook",A.nF(new A.lz(s,r)),"function_commit_hook",A.aK(new A.lA(s)),"function_rollback_hook",A.aK(new A.lB(s)),"localtime",A.b4(new A.lC(r)),"changeset_apply_filter",A.b4(new A.lD(s)),"changeset_apply_conflict",A.eN(new A.lE(s))],q,p)],q,t.dY)}}
A.lh.prototype={
$1(a){A.vt("[sqlite3] "+A.bE(this.a,a,null))},
$S:5}
A.li.prototype={
$5(a,b,c,d,e){var s,r=this.a,q=r.d.e.j(0,a)
q.toString
s=this.b
return A.at(new A.l8(r,q,new A.dZ(A.nm(s,b,null)),d,s,c,e))},
$C:"$5",
$R:5,
$S:24}
A.l8.prototype={
$0(){var s,r,q=this,p=q.b.aE(q.c,q.d),o=q.a.d,n=o.a++
o.f.p(0,n,p.a)
o=q.e
s=A.bw(o.buffer,0,null)
r=B.b.I(q.f,2)
s.$flags&2&&A.v(s)
s[r]=n
n=q.r
if(n!==0){o=A.bw(o.buffer,0,null)
n=B.b.I(n,2)
o.$flags&2&&A.v(o)
o[n]=p.b}},
$S:0}
A.lj.prototype={
$3(a,b,c){var s=this.a.d.e.j(0,a)
s.toString
return A.at(new A.l7(s,A.bE(this.b,b,null),c))},
$C:"$3",
$R:3,
$S:16}
A.l7.prototype={
$0(){return this.a.cE(this.b,this.c)},
$S:0}
A.lu.prototype={
$4(a,b,c,d){var s,r=this.a.d.e.j(0,a)
r.toString
s=this.b
return A.at(new A.l6(r,A.bE(s,b,null),c,s,d))},
$C:"$4",
$R:4,
$S:23}
A.l6.prototype={
$0(){var s=this,r=s.a.bP(s.b,s.c),q=A.bw(s.d.buffer,0,null),p=B.b.I(s.e,2)
q.$flags&2&&A.v(q)
q[p]=r},
$S:0}
A.lF.prototype={
$4(a,b,c,d){var s,r=this.a.d.e.j(0,a)
r.toString
s=this.b
return A.at(new A.l5(r,A.bE(s,b,null),c,s,d))},
$C:"$4",
$R:4,
$S:23}
A.l5.prototype={
$0(){var s,r,q=this,p=B.h.ac(q.a.cF(q.b)),o=p.length
if(o>q.c)throw A.a(A.bC(14))
s=A.aF(q.d.buffer,0,null)
r=q.e
B.d.aF(s,r,p)
s.$flags&2&&A.v(s)
s[r+o]=0},
$S:0}
A.lG.prototype={
$3(a,b,c){return A.at(new A.lg(this.b,c,b,this.a.d.e.j(0,a)))},
$C:"$3",
$R:3,
$S:16}
A.lg.prototype={
$0(){var s=this,r=A.aF(s.a.buffer,s.b,s.c),q=s.d
if(q!=null)A.o2(r,q.b)
else return A.o2(r,null)},
$S:0}
A.lH.prototype={
$2(a,b){var s=this.a.d.e.j(0,a)
s.toString
return A.at(new A.lf(s,b))},
$S:3}
A.lf.prototype={
$0(){this.a.cI(A.oh(this.b,0))},
$S:0}
A.lI.prototype={
$2(a,b){var s
this.a.d.e.j(0,a).toString
s=v.G.BigInt(Date.now())
A.fq(A.ow(this.b.buffer,0,null),"setBigInt64",b,s,!0,null)},
$S:48}
A.lJ.prototype={
$1(a){return this.a.d.f.j(0,a).gdS()},
$S:14}
A.lK.prototype={
$1(a){var s=this.a,r=s.d.f.j(0,a)
r.toString
return A.at(new A.le(s,r,a))},
$S:14}
A.le.prototype={
$0(){this.b.bQ()
this.a.d.f.u(0,this.c)},
$S:0}
A.lL.prototype={
$4(a,b,c,d){var s=this.a.d.f.j(0,a)
s.toString
return A.at(new A.ld(s,this.b,b,c,d))},
$C:"$4",
$R:4,
$S:25}
A.ld.prototype={
$0(){var s=this
s.a.cH(A.aF(s.b.buffer,s.c,s.d),A.r(v.G.Number(s.e)))},
$S:0}
A.lk.prototype={
$4(a,b,c,d){var s=this.a.d.f.j(0,a)
s.toString
return A.at(new A.lc(s,this.b,b,c,d))},
$C:"$4",
$R:4,
$S:25}
A.lc.prototype={
$0(){var s=this
s.a.aW(A.aF(s.b.buffer,s.c,s.d),A.r(v.G.Number(s.e)))},
$S:0}
A.ll.prototype={
$2(a,b){var s=this.a.d.f.j(0,a)
s.toString
return A.at(new A.lb(s,b))},
$S:50}
A.lb.prototype={
$0(){return this.a.bm(A.r(v.G.Number(this.b)))},
$S:0}
A.lm.prototype={
$2(a,b){var s=this.a.d.f.j(0,a)
s.toString
return A.at(new A.la(s,b))},
$S:3}
A.la.prototype={
$0(){return this.a.cJ(this.b)},
$S:0}
A.ln.prototype={
$2(a,b){var s=this.a.d.f.j(0,a)
s.toString
return A.at(new A.l9(s,this.b,b))},
$S:3}
A.l9.prototype={
$0(){var s=this.a.bl(),r=A.bw(this.b.buffer,0,null),q=B.b.I(this.c,2)
r.$flags&2&&A.v(r)
r[q]=s},
$S:0}
A.lo.prototype={
$2(a,b){var s=this.a.d.f.j(0,a)
s.toString
return A.at(new A.l4(s,b))},
$S:3}
A.l4.prototype={
$0(){return this.a.cG(this.b)},
$S:0}
A.lp.prototype={
$2(a,b){var s=this.a.d.f.j(0,a)
s.toString
return A.at(new A.l3(s,b))},
$S:3}
A.l3.prototype={
$0(){return this.a.cK(this.b)},
$S:0}
A.lq.prototype={
$2(a,b){var s=this.a.d.f.j(0,a)
s.toString
return A.at(new A.l2(s,this.b,b))},
$S:3}
A.l2.prototype={
$0(){var s=this.a.cD(),r=A.bw(this.b.buffer,0,null),q=B.b.I(this.c,2)
r.$flags&2&&A.v(r)
r[q]=s},
$S:0}
A.lr.prototype={
$3(a,b,c){var s=this.a,r=s.a
r===$&&A.O()
r=s.d.b.j(0,r.d.sqlite3_user_data(a)).a
s=s.a
r.$2(new A.bD(s,a),new A.d3(s,b,c))},
$C:"$3",
$R:3,
$S:17}
A.ls.prototype={
$3(a,b,c){var s=this.a,r=s.a
r===$&&A.O()
r=s.d.b.j(0,r.d.sqlite3_user_data(a)).b
s=s.a
r.$2(new A.bD(s,a),new A.d3(s,b,c))},
$C:"$3",
$R:3,
$S:17}
A.lt.prototype={
$3(a,b,c){var s=this.a,r=s.a
r===$&&A.O()
s.d.b.j(0,r.d.sqlite3_user_data(a)).toString
s=s.a
null.$2(new A.bD(s,a),new A.d3(s,b,c))},
$C:"$3",
$R:3,
$S:17}
A.lv.prototype={
$1(a){var s=this.a,r=s.a
r===$&&A.O()
s.d.b.j(0,r.d.sqlite3_user_data(a)).c.$1(new A.bD(s.a,a))},
$S:5}
A.lw.prototype={
$1(a){var s=this.a,r=s.a
r===$&&A.O()
s.d.b.j(0,r.d.sqlite3_user_data(a)).toString
null.$1(new A.bD(s.a,a))},
$S:5}
A.lx.prototype={
$1(a){this.a.d.b.u(0,a)},
$S:5}
A.ly.prototype={
$5(a,b,c,d,e){var s=this.b,r=A.nm(s,c,b),q=A.nm(s,e,d)
this.a.d.b.j(0,a).toString
return null.$2(r,q)},
$C:"$5",
$R:5,
$S:24}
A.lz.prototype={
$5(a,b,c,d,e){var s=A.bE(this.b,d,null),r=this.a.d.w
if(r!=null)r.$3(b,s,A.r(v.G.Number(e)))},
$C:"$5",
$R:5,
$S:104}
A.lA.prototype={
$1(a){var s=this.a.d.x
return s==null?null:s.$0()},
$S:53}
A.lB.prototype={
$1(a){var s=this.a.d.y
if(s!=null)s.$0()},
$S:5}
A.lC.prototype={
$2(a,b){var s=new A.dB(A.og(A.r(v.G.Number(a))*1000,0,!1),0,!1),r=A.rU(this.a.buffer,b,8)
r.$flags&2&&A.v(r)
r[0]=A.oF(s)
r[1]=A.oD(s)
r[2]=A.oC(s)
r[3]=A.oB(s)
r[4]=A.oE(s)-1
r[5]=A.oG(s)-1900
r[6]=B.b.a7(A.t_(s),7)},
$S:54}
A.lD.prototype={
$2(a,b){return this.a.d.r.j(0,a).gjk().$1(b)},
$S:3}
A.lE.prototype={
$3(a,b,c){return this.a.d.r.j(0,a).gjj().$2(b,c)},
$C:"$3",
$R:3,
$S:16}
A.ih.prototype={
iX(a){var s=this.a++
this.b.p(0,s,a)
return s}}
A.fP.prototype={}
A.mi.prototype={
$1(a){var s=a.data,r=J.a_(s,"_disconnect"),q=this.a.a
if(r){q===$&&A.O()
r=q.a
r===$&&A.O()
r.q()}else{q===$&&A.O()
r=q.a
r===$&&A.O()
r.E(0,A.n8(A.a9(s)))}},
$S:1}
A.mj.prototype={
$1(a){a.fj(this.a)},
$S:27}
A.mk.prototype={
$0(){var s=this.a
s.postMessage("_disconnect")
s.close()
s=this.b
if(s!=null)s.a.aN()},
$S:0}
A.ml.prototype={
$1(a){var s=this.a.a
s===$&&A.O()
s=s.a
s===$&&A.O()
s.q()
a.a.aN()},
$S:56}
A.fN.prototype={
fv(a){var s=this.a.b
s===$&&A.O()
new A.as(s,A.D(s).h("as<1>")).iK(this.gh8(),new A.je(this))},
bX(a){return this.h9(a)},
h9(a1){var s=0,r=A.j(t.H),q=1,p=[],o=[],n=this,m,l,k,j,i,h,g,f,e,d,c,b,a,a0
var $async$bX=A.k(function(a2,a3){if(a2===1){p.push(a3)
s=q}for(;;)switch(s){case 0:i=a1 instanceof A.ak
h=null
g=null
if(i){h=a1.a
g=h}if(i){f=n.c.u(0,g)
if(f!=null)f.O(a1)
s=2
break}s=a1 instanceof A.cW?3:4
break
case 3:m=null
f=n.d
e=a1.a
d=v.G
c=new d.AbortController()
f.p(0,e,c)
l=c
q=6
e=a1.a2(n,l.signal)
s=9
return A.c(t.gy.b(e)?e:A.kP(e,t.q),$async$bX)
case 9:m=a3
o.push(8)
s=7
break
case 6:q=5
a0=p.pop()
k=A.W(a0)
j=A.al(a0)
if(!(k instanceof A.bm)){d.console.error("Error in worker: "+J.bl(k))
d.console.error("Original trace: "+A.y(j))}m=new A.br(J.bl(k),k,a1.a)
o.push(8)
s=7
break
case 5:o=[1]
case 7:q=1
f.u(0,a1.a)
s=o.pop()
break
case 8:f=n.a.a
f===$&&A.O()
f.E(0,m)
s=2
break
case 4:if(a1 instanceof A.dT){s=2
break}i=a1 instanceof A.bn
if(i)g=a1.a
else g=null
if(i){a=n.d.u(0,g)
if(a!=null)a.abort()
s=2
break}if(a1 instanceof A.b_)throw A.a(A.L("Should only be a top-level message"))
case 2:return A.h(null,r)
case 1:return A.f(p.at(-1),r)}})
return A.i($async$bX,r)},
bS(a,b,c){return this.fi(a,b,c,c)},
fi(a,b,c,d){var s=0,r=A.j(d),q,p=this,o,n,m,l
var $async$bS=A.k(function(e,f){if(e===1)return A.f(f,r)
for(;;)switch(s){case 0:m=p.b++
l=new A.m($.q,t.fO)
p.c.p(0,m,new A.H(l,t.ex))
o=p.a.a
o===$&&A.O()
a.a=m
o.E(0,a)
s=3
return A.c(l,$async$bS)
case 3:n=f
if(n.gJ()===b){q=c.a(n)
s=1
break}else throw A.a(n.eN())
case 1:return A.h(q,r)}})
return A.i($async$bS,r)},
c5(a){var s=0,r=A.j(t.H),q=this,p,o
var $async$c5=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:o=q.a.a
o===$&&A.O()
s=2
return A.c(o.q(),$async$c5)
case 2:for(o=q.c,p=new A.cM(o,o.r,o.e);p.l();)p.d.a4(new A.b0("Channel closed before receiving response: "+A.y(a)))
o.aw(0)
return A.h(null,r)}})
return A.i($async$c5,r)}}
A.je.prototype={
$1(a){this.a.c5(a)},
$S:11}
A.ii.prototype={
aq(a){return this.iL(a)},
iL(a){var s=0,r=A.j(t.n),q
var $async$aq=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:q=A.k5(a,null)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$aq,r)}}
A.cf.prototype={}
A.k9.prototype={
eZ(a,b){var s,r=new A.m($.q,t.cp),q=new A.H(r,t.eP),p={}
if(b!=null)p.signal=b
s=t.X
A.n_(A.Q(this.a.request(a,p,A.aK(new A.ka(q))),s),new A.kb(q),s,t.K)
return r},
eY(a){return this.eZ(a,null)}}
A.ka.prototype={
$1(a){var s=new A.m($.q,t.D)
this.a.O(new A.bt(new A.H(s,t.F)))
return A.rw(s)},
$S:57}
A.kb.prototype={
$2(a,b){var s
A.a9(a)
s=this.a
if((s.a.a&30)===0)if(J.a_(a.name,"AbortError"))s.aO(new A.bm("Operation was cancelled"),b)
else s.aO(a,b)
return null},
$S:58}
A.bt.prototype={
j_(){return this.a.aN()}}
A.iw.prototype={
bf(a,b,c){return this.iN(a,b,c,c)},
iN(a,b,c,d){var s=0,r=A.j(d),q,p=this,o
var $async$bf=A.k(function(e,f){if(e===1)return A.f(f,r)
for(;;)switch(s){case 0:s=p.c?3:4
break
case 3:s=5
return A.c($.mS().eZ(p.a,b),$async$bf)
case 5:o=f
q=A.oj(a,c).W(o.giZ())
s=1
break
case 4:q=p.b.cA(a,b,c)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$bf,r)}}
A.fz.prototype={
cA(a,b,c){return this.jd(a,b,c,c)},
jc(a,b){return this.cA(a,null,b)},
jd(a,b,c,d){var s=0,r=A.j(d),q,p=this,o,n,m,l,k,j,i,h,g,f
var $async$cA=A.k(function(e,a0){if(e===1)return A.f(a0,r)
for(;;)switch(s){case 0:f={}
f.a=!1
o=new A.j8(f,p)
if(!p.a){f.a=p.a=!0
q=A.dH(a,c).W(o)
s=1
break}else{n=new A.m($.q,c.h("m<0>"))
m=new A.H(n,c.h("H<0>"))
f=new A.j7(f,m,a,c)
l=A.pc()
l.b=A.ag(b,"abort",new A.j6(p,l,m,f),!1,t.m)
k=p.b
j=k.a
i=k.c
j[i]=f
j=j.length
i=(i+1&j-1)>>>0
k.c=i
if(k.b===i){h=A.an(j*2,null,!1,k.$ti.h("1?"))
f=k.a
j=k.b
g=f.length-j
B.c.H(h,0,g,f,j)
B.c.H(h,g,g+k.b,k.a,0)
k.b=0
k.c=k.a.length
k.a=h}++k.d
q=n.W(o)
s=1
break}case 1:return A.h(q,r)}})
return A.i($async$cA,r)}}
A.j8.prototype={
$0(){var s,r,q,p
if(!this.a.a)return
s=this.b
r=s.b
if(!r.gv(0)){s=r.b
if(s===r.c)A.C(A.fm());++r.d
q=r.a
p=q[s]
if(p==null)p=r.$ti.c.a(p)
q[s]=null
r.b=(s+1&q.length-1)>>>0
p.$0()}else s.a=!1},
$S:0}
A.j7.prototype={
$0(){var s=this
s.a.a=!0
s.b.O(A.dH(s.c,s.d))},
$S:0}
A.j6.prototype={
$1(a){var s,r=this
r.b.ej().B()
s=r.c
if((s.a.a&30)===0){r.a.b.u(0,r.d)
s.a4(B.K)}},
$S:1}
A.w.prototype={
ae(){return"MessageType."+this.b}}
A.A.prototype={
G(a,b){a.t=this.gJ().b},
dT(a){var s={},r=A.n([],t.W)
this.G(s,r)
a.$2(s,r)},
cL(a){this.dT(new A.j5(a))},
fj(a){this.dT(new A.j4(a))}}
A.j5.prototype={
$2(a,b){return this.a.postMessage(a,b)},
$S:28}
A.j4.prototype={
$2(a,b){return this.a.postMessage(a,b)},
$S:28}
A.dT.prototype={}
A.jm.prototype={}
A.cW.prototype={
G(a,b){var s
this.b1(a,b)
a.i=this.a
s=this.b
if(s!=null)a.d=s}}
A.ak.prototype={
G(a,b){this.b1(a,b)
a.i=this.a},
eN(){return new A.cV("Did not respond with expected type, got "+this.i(0))}}
A.bs.prototype={
ae(){return"FileSystemImplementation."+this.b}}
A.c5.prototype={
gJ(){return B.a2},
G(a,b){var s=this
s.ai(a,b)
a.d=s.d
a.s=s.e.c
a.u=s.c.i(0)
a.o=s.f
a.a=s.r},
a2(a,b){return a.bb(this,b)}}
A.b6.prototype={
gJ(){return B.a4},
G(a,b){var s
this.ai(a,b)
s=this.c
a.r=s
b.push(s.port)},
a2(a,b){return a.du(this,b)}}
A.b_.prototype={
gJ(){return B.a6},
G(a,b){this.b1(a,b)
a.r=this.a}}
A.bp.prototype={
gJ(){return B.a1},
G(a,b){this.ai(a,b)
a.r=this.c},
a2(a,b){return a.ba(this,b)}}
A.bW.prototype={
gJ(){return B.a9},
G(a,b){this.ai(a,b)
a.f=this.c.a},
a2(a,b){return a.ck(this,b)}}
A.bX.prototype={
gJ(){return B.aa},
a2(a,b){return a.bH(this,b)}}
A.bV.prototype={
gJ(){return B.V},
G(a,b){var s
this.ai(a,b)
s=this.c
a.b=s
a.f=this.d.a
if(s!=null)b.push(s)},
a2(a,b){return a.cj(this,b)}}
A.c9.prototype={
gJ(){return B.a3},
G(a,b){var s,r,q,p=this
p.ai(a,b)
a.s=p.c
a.r=p.f
s=p.e
if(s==null)s=null
a.z=s
s=p.d
if(s.length!==0){r=A.nk(s)
q=r.b
a.p=r.a
a.v=q
b.push(q)}else a.p=new v.G.Array()
a.c=p.r},
a2(a,b){return a.cm(this,b)}}
A.c8.prototype={
gJ(){return B.a_},
a2(a,b){return a.ci(this,b)}}
A.c7.prototype={
G(a,b){this.ai(a,b)
a.z=this.c},
gJ(){return B.X},
a2(a,b){var s=a.aj(this),r=s.f,q=r==null?null:r.a
if(q!==this.c)A.C(A.L("Lock to be released is not active."))
r.b.aN()
s.f=null
return new A.X(null,this.a)}}
A.bP.prototype={
gJ(){return B.W},
a2(a,b){return a.cf(this,b)}}
A.c4.prototype={
gJ(){return B.a5},
a2(a,b){return a.cl(this,b)}}
A.X.prototype={
gJ(){return B.w},
G(a,b){var s
this.bT(a,b)
s=this.b
a.r=s
if(s instanceof v.G.ArrayBuffer)b.push(A.a9(s))}}
A.bq.prototype={
gJ(){return B.Z},
G(a,b){var s
this.bT(a,b)
s=this.b
a.r=s
b.push(s.port)}}
A.aQ.prototype={
ae(){return"TypeCode."+this.b},
eI(a){var s=null
switch(this.a){case 0:s=A.q6(a)
break
case 1:a=A.r(A.z(a))
s=a
break
case 2:s=A.pa(t.fV.a(a).toString(),null)
break
case 3:A.z(a)
s=a
break
case 4:A.ah(a)
s=a
break
case 5:t.Z.a(a)
s=a
break
case 7:A.aR(a)
s=a
break
case 6:break}return s}}
A.aZ.prototype={
gJ(){return B.a8},
G(a,b){var s,r=this
r.bT(a,b)
a.x=r.c
a.y=r.d
s=r.b
if(s!=null)A.t9(a,b,s)}}
A.br.prototype={
gJ(){return B.a7},
G(a,b){var s
this.bT(a,b)
a.e=this.b
s=this.c
if(s!=null&&s instanceof A.ca){a.s=0
a.r=A.ro(s)}else if(s instanceof A.bm)a.s=1},
eN(){var s=this.c
if(s!=null&&s instanceof A.bm)return s
return new A.cV(this.b)}}
A.iC.prototype={
$1(a){if(a!=null)return A.ah(a)
return null},
$S:60}
A.cb.prototype={
G(a,b){this.ai(a,b)
a.a=this.c},
a2(a,b){return a.bc(this,b)},
gJ(){return this.d}}
A.b5.prototype={
G(a,b){var s
this.ai(a,b)
s=this.d
if(s==null)s=null
a.d=s},
a2(a,b){return a.cg(this,b)},
gJ(){return this.c}}
A.bR.prototype={
gf4(){var s,r,q,p,o,n=this,m=t.s,l=A.n([],m)
for(s=n.a,r=s.length,q=0;q<s.length;s.length===r||(0,A.R)(s),++q){p=s[q]
B.c.am(l,A.n([p.a.b,p.b],m))}o={}
o.a=l
o.b=n.b
o.c=n.c
o.d=n.e
o.e=n.f
o.f=n.r
o.g=n.d
return o}}
A.bB.prototype={
gJ(){return B.Y},
G(a,b){var s
this.b1(a,b)
a.d=this.b
s=this.a
a.k=s.a.a
a.u=s.b
a.r=s.c}}
A.aU.prototype={
G(a,b){this.b1(a,b)
a.d=this.a},
gJ(){return this.b}}
A.bn.prototype={
gJ(){return B.a0},
G(a,b){this.b1(a,b)
a.i=this.a}}
A.mt.prototype={
$1(a){this.b.transaction.abort()
this.a.a=!1},
$S:15}
A.i2.prototype={
$1(a){this.a.O(this.c.a(this.b.result))},
$S:1}
A.i3.prototype={
$1(a){var s=this.b.error
if(s==null)s=a
this.a.a4(s)},
$S:1}
A.i6.prototype={
$1(a){this.a.O(this.c.a(this.b.result))},
$S:1}
A.i7.prototype={
$1(a){var s=this.b.error
if(s==null)s=a
this.a.a4(s)},
$S:1}
A.i8.prototype={
$1(a){var s=this.b.error
if(s==null)s=a
this.a.a4(s)},
$S:1}
A.dF.prototype={
ae(){return"FileType."+this.b}}
A.bz.prototype={
ae(){return"StorageMode."+this.b}}
A.cV.prototype={
i(a){return"Remote error: "+this.a},
$ia6:1}
A.bm.prototype={}
A.kd.prototype={}
A.fc.prototype={
gf6(){var s=t.U
return new A.cl(new A.iA(),new A.ci(this.a,"message",!1,s),s.h("cl<a1.T,A>"))}}
A.iA.prototype={
$1(a){return A.n8(A.a9(a.data))},
$S:61}
A.jp.prototype={
gf6(){return new A.bh(!1,new A.jt(this),t.dZ)}}
A.jt.prototype={
$1(a){var s=A.n([],t.W),r=A.n([],t.db)
r.push(A.ag(this.a.a,"connect",new A.jq(new A.ju(s,r,a)),!1,t.m))
a.r=new A.jr(r)},
$S:62}
A.ju.prototype={
$1(a){this.a.push(a)
a.start()
this.b.push(A.ag(a,"message",new A.js(this.c),!1,t.m))},
$S:1}
A.js.prototype={
$1(a){this.a.i3(A.n8(A.a9(a.data)))},
$S:1}
A.jq.prototype={
$1(a){var s,r=a.ports
r=J.ae(t.cl.b(r)?r:new A.bO(r,A.ac(r).h("bO<1,e>")))
s=this.a
while(r.l())s.$1(r.gm())},
$S:1}
A.jr.prototype={
$0(){var s,r,q
for(s=this.a,r=s.length,q=0;q<s.length;s.length===r||(0,A.R)(s),++q)s[q].B()},
$S:4}
A.eB.prototype={
B(){var s=this.a
if(s!=null)s.B()
this.a=null}}
A.d5.prototype={
q(){var s=0,r=A.j(t.H),q=this,p,o,n
var $async$q=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:q.c.B()
q.d.B()
q.e.B()
for(p=q.w,o=p.length,n=0;n<p.length;p.length===o||(0,A.R)(p),++n)p[n].abort()
B.c.aw(p)
p=q.f
if(p!=null)p.b.aN()
s=2
return A.c(q.a.bE(),$async$q)
case 2:return A.h(null,r)}})
return A.i($async$q,r)},
en(a){var s,r=new v.G.AbortController(),q=new A.kC(r)
if(typeof q=="function")A.C(A.M("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(){return b(c)}}(A.uc,q)
s[$.cD()]=q
a.onabort=s
this.w.push(r)
return r},
jb(a,b,c,d){var s,r,q=this
if(a==null){s=q.a.f
if(!(!s.c&&!s.b.a)){r=q.en(b)
return s.bf(c,r.signal,d).W(new A.kG(q,r))}}else{s=q.f
if((s==null?null:s.a)!==a)throw A.a(A.L("Requested operation on inactive lock state."))}return A.dH(c,d)},
iQ(a){var s=this,r=s.en(a),q=new A.m($.q,t.fJ),p=new A.b2(q,t.bS),o=t.H
A.n_(s.a.f.bf(new A.kD(s,p),r.signal,o),new A.kE(p),o,t.K)
return q.W(new A.kF(s,r))}}
A.kC.prototype={
$0(){return this.a.abort()},
$S:0}
A.kG.prototype={
$0(){B.c.u(this.a.w,this.b)},
$S:4}
A.kD.prototype={
$0(){var s=this.a,r=s.r++,q=new A.m($.q,t.D)
s.f=new A.aB(r,new A.b2(q,t.h))
this.b.O(r)
return q},
$S:2}
A.kE.prototype={
$2(a,b){var s=this.a
if((s.a.a&30)===0)s.aO(a,b)},
$S:12}
A.kF.prototype={
$0(){B.c.u(this.a.w,this.b)},
$S:4}
A.ef.prototype={
fz(a,b,c){var s=this.a.a
s===$&&A.O()
s.c.a.W(new A.ku(this))},
cg(a,b){return this.io(a,b)},
io(a,b){var s=0,r=A.j(t.q),q,p=this,o
var $async$cg=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:o=A
s=3
return A.c(p.e.eF(a),$async$cg)
case 3:q=new o.X(d.gf4(),a.a)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$cg,r)},
du(a,b){return this.ip(a,b)},
ip(a,b){var s=0,r=A.j(t.q),q,p=this
var $async$du=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:new A.b6(a.c,0,null).cL(p.e.f8())
q=new A.X(null,a.a)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$du,r)},
ba(a,b){return this.iq(a,b)},
iq(a,b){var s=0,r=A.j(t.q),q,p=this,o,n,m
var $async$ba=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:o=a.b
n=a.c
s=o!=null?3:5
break
case 3:s=7
return A.c(p.e8(o).a.gar(),$async$ba)
case 7:s=6
return A.c(d.bG(p,n),$async$ba)
case 6:s=4
break
case 5:s=8
return A.c(p.e.b.bG(p,n),$async$ba)
case 8:case 4:m=d
q=new A.X(m,a.a)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$ba,r)},
bb(a,b){return this.ix(a,b)},
ix(a,b){var s=0,r=A.j(t.q),q,p=2,o=[],n=this,m,l,k,j,i,h
var $async$bb=A.k(function(c,d){if(c===1){o.push(d)
s=p}for(;;)switch(s){case 0:i=n.e
s=3
return A.c(i.aq(a.c),$async$bb)
case 3:m=null
l=null
p=5
m=i.ii(a.d,a.e,a.r)
s=8
return A.c(a.f?m.gaD():m.gar(),$async$bb)
case 8:l=A.pd(m,null)
n.f.push(l)
k=m.b
i=a.a
q=new A.X(k,i)
s=1
break
p=2
s=7
break
case 5:p=4
h=o.pop()
s=m!=null?9:10
break
case 9:B.c.u(n.f,l)
s=11
return A.c(m.bE(),$async$bb)
case 11:case 10:throw h
s=7
break
case 4:s=2
break
case 7:case 1:return A.h(q,r)
case 2:return A.f(o.at(-1),r)}})
return A.i($async$bb,r)},
cm(a,b){return this.iz(a,b)},
iz(a,b){var s=0,r=A.j(t.q),q,p=this,o,n,m,l,k
var $async$cm=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:o=p.aj(a)
n=o
m=a.e
l=b
k=A
s=3
return A.c(o.a.gar(),$async$cm)
case 3:q=n.jb(m,l,new k.kv(d,a),t.q)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$cm,r)},
ci(a,b){return this.it(a,b)},
it(a,b){var s=0,r=A.j(t.q),q,p=this,o
var $async$ci=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:o=A
s=3
return A.c(p.aj(a).iQ(b),$async$ci)
case 3:q=new o.X(d,a.a)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$ci,r)},
bc(a,b){return this.iA(a,b)},
iA(a,b){var s=0,r=A.j(t.q),q,p=this,o,n,m
var $async$bc=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:m=p.aj(a)
s=a.c?3:5
break
case 3:case 6:switch(a.d.a){case 11:s=8
break
case 13:s=9
break
case 12:s=10
break
default:s=11
break}break
case 8:s=12
return A.c(p.b0(m.c,new A.kz(p,m),a),$async$bc)
case 12:q=d
s=1
break
case 9:s=13
return A.c(p.b0(m.e,new A.kA(p,m),a),$async$bc)
case 13:q=d
s=1
break
case 10:s=14
return A.c(p.b0(m.d,new A.kB(p,m),a),$async$bc)
case 14:q=d
s=1
break
case 11:throw A.a(A.M("Unknown stream to subscribe to",null))
case 7:s=4
break
case 5:o=a.d
A:{if(B.B===o){n=m.c
break A}if(B.v===o){n=m.d
break A}if(B.z===o){n=m.e
break A}n=A.C(A.M("Unknown stream to unsubscribe from",null))}n.B()
q=new A.X(null,a.a)
s=1
break
case 4:case 1:return A.h(q,r)}})
return A.i($async$bc,r)},
cl(a,b){return this.iy(a,b)},
iy(a,b){var s=0,r=A.j(t.q),q,p=this,o,n,m
var $async$cl=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:m=p.aj(a).a;++m.r
s=3
return A.c(A.mv(),$async$cl)
case 3:o=d
n=o.a
p.e.dZ(o.b).f.push(A.pd(m,0))
q=new A.bq(n,a.a)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$cl,r)},
cf(a,b){return this.im(a,b)},
im(a,b){var s=0,r=A.j(t.q),q,p=this,o
var $async$cf=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:o=p.aj(a)
B.c.u(p.f,o)
s=3
return A.c(o.q(),$async$cf)
case 3:q=new A.X(null,a.a)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$cf,r)},
bH(a,b){return this.iw(a,b)},
iw(a,b){var s=0,r=A.j(t.q),q,p=this,o
var $async$bH=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:s=3
return A.c(p.aj(a).a.gaD(),$async$bH)
case 3:o=d
s=o instanceof A.bY?4:5
break
case 4:s=6
return A.c(o.il(),$async$bH)
case 6:case 5:q=new A.X(null,a.a)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$bH,r)},
cj(a,b){return this.iu(a,b)},
iu(a,b){var s=0,r=A.j(t.q),q,p=[],o=this,n,m,l,k,j,i
var $async$cj=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:j=a.c
s=3
return A.c(o.aj(a).a.gaD(),$async$cj)
case 3:i=d.aE(new A.dZ(A.pM(a.d)),4).a
try{if(j!=null){n=j
i.bm(n.byteLength)
i.aW(A.aF(n,0,null),0)
l=a.a
q=new A.X(null,l)
s=1
break}else{l=i.bl()
m=new Uint8Array(l)
i.cH(m,0)
l=t.a.a(J.qV(m))
k=a.a
q=new A.X(l,k)
s=1
break}}finally{i.bQ()}case 1:return A.h(q,r)}})
return A.i($async$cj,r)},
ck(a,b){return this.iv(a,b)},
iv(a,b){var s=0,r=A.j(t.q),q,p=this,o
var $async$ck=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)switch(s){case 0:o=A
s=3
return A.c(p.aj(a).a.gaD(),$async$ck)
case 3:q=new o.X(d.bP(A.pM(a.c),0)===1,a.a)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$ck,r)},
b0(a,b,c){return this.fn(a,b,c)},
fn(a,b,c){var s=0,r=A.j(t.q),q,p
var $async$b0=A.k(function(d,e){if(d===1)return A.f(e,r)
for(;;)switch(s){case 0:s=a.a==null?3:4
break
case 3:p=a
s=5
return A.c(b.$0(),$async$b0)
case 5:p.a=e
case 4:q=new A.X(null,c.a)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$b0,r)},
c9(a){var s=0,r=A.j(t.X),q,p=this
var $async$c9=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:s=3
return A.c(p.bS(new A.bp(a,0,null),B.w,t.cs),$async$c9)
case 3:q=c.b
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$c9,r)},
e8(a){return B.c.ik(this.f,new A.kt(a))},
aj(a){var s=a.b
if(s!=null)return this.e8(s)
else throw A.a(A.M("Request requires database id",null))},
$ioa:1}
A.ku.prototype={
$0(){var s=0,r=A.j(t.H),q=this,p,o,n
var $async$$0=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:p=q.a.f,o=p.length,n=0
case 2:if(!(n<p.length)){s=4
break}s=5
return A.c(p[n].q(),$async$$0)
case 5:case 3:p.length===o||(0,A.R)(p),++n
s=2
break
case 4:B.c.aw(p)
return A.h(null,r)}})
return A.i($async$$0,r)},
$S:2}
A.kv.prototype={
$0(){var s,r,q,p=this.a.a,o=this.b
if(o.r){s=p.b
s=s.a.d.sqlite3_get_autocommit(s.b)!==0}else s=!1
if(s)throw A.a(A.L("Database is not in a transaction"))
s=o.c
r=o.d
if(o.f)q=p.fh(s,r)
else{p.eL(s,r)
q=null}o=o.a
s=p.b
r=s.b
s=s.a.d
return new A.aZ(q,s.sqlite3_get_autocommit(r)!==0,A.r(v.G.Number(s.sqlite3_last_insert_rowid(r))),o)},
$S:63}
A.kz.prototype={
$0(){var s=0,r=A.j(t.aY),q,p=this,o
var $async$$0=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:o=p.b
s=3
return A.c(o.a.gar(),$async$$0)
case 3:q=b.a.ex().gbo().aQ(new A.ky(p.a,o))
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$$0,r)},
$S:64}
A.ky.prototype={
$1(a){var s=this.a.a.a
s===$&&A.O()
s.E(0,new A.bB(a,this.b.b))},
$S:29}
A.kA.prototype={
$0(){var s=0,r=A.j(t.fY),q,p=this,o
var $async$$0=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:o=p.b
s=3
return A.c(o.a.gar(),$async$$0)
case 3:q=b.a.d_().gbo().aQ(new A.kx(p.a,o))
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$$0,r)},
$S:30}
A.kx.prototype={
$1(a){var s=this.a.a.a
s===$&&A.O()
s.E(0,new A.aU(this.b.b,B.C))},
$S:9}
A.kB.prototype={
$0(){var s=0,r=A.j(t.fY),q,p=this,o
var $async$$0=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:o=p.b
s=3
return A.c(o.a.gar(),$async$$0)
case 3:q=b.a.hD().gbo().aQ(new A.kw(p.a,o))
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$$0,r)},
$S:30}
A.kw.prototype={
$1(a){var s=this.a.a.a
s===$&&A.O()
s.E(0,new A.aU(this.b.b,B.x))},
$S:9}
A.kt.prototype={
$1(a){return a.b===this.a},
$S:68}
A.fa.prototype={
gaD(){var s=0,r=A.j(t.l),q,p=this,o
var $async$gaD=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:o=p.x
s=3
return A.c(o==null?p.x=A.dH(new A.iz(p),t.H):o,$async$gaD)
case 3:o=p.y
o.toString
q=o
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$gaD,r)},
gar(){var s=0,r=A.j(t.u),q,p=this,o
var $async$gar=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:o=p.w
s=3
return A.c(o==null?p.w=A.dH(new A.iy(p),t.u):o,$async$gar)
case 3:q=b
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$gar,r)},
bE(){var s=0,r=A.j(t.H),q=this
var $async$bE=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:s=--q.r===0?2:3
break
case 2:s=4
return A.c(q.q(),$async$bE)
case 4:case 3:return A.h(null,r)}})
return A.i($async$bE,r)},
q(){var s=0,r=A.j(t.H),q=this,p,o,n,m,l,k
var $async$q=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:k=q.a.r
k.toString
s=2
return A.c(k,$async$q)
case 2:p=b
k=q.w
k.toString
s=3
return A.c(k,$async$q)
case 3:b.a.an()
o=q.y
if(o!=null){k=p.a
n=$.nT()
m=n.a.get(o)
if(m==null)A.C(A.L("vfs has not been registered"))
l=m+16
k=k.b
n=k.d
n.sqlite3_vfs_unregister(m)
n.dart_sqlite3_free(l)
k.c.e.u(0,A.bw(k.b.buffer,0,null)[B.b.I(l+4,2)])}k=q.z
k=k==null?null:k.$0()
s=4
return A.c(k instanceof A.m?k:A.kP(k,t.H),$async$q)
case 4:return A.h(null,r)}})
return A.i($async$q,r)}}
A.iz.prototype={
$0(){var s=0,r=A.j(t.H),q=this,p,o,n,m,l,k,j,i,h,g,f,e
var $async$$0=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:e=q.a
case 2:switch(e.d.a){case 1:s=4
break
case 0:s=5
break
case 2:s=6
break
case 3:s=7
break
case 4:s=8
break
default:s=3
break}break
case 4:p=v.G
o=new p.SharedArrayBuffer(8)
n=p.Int32Array
n=t.ha.a(A.cw(n,[o]))
p.Atomics.store(n,0,-1)
n={clientVersion:1,root:"drift_db/"+e.c,synchronizationBuffer:o,communicationBuffer:new p.SharedArrayBuffer(67584)}
m=new p.Worker(A.e5().i(0))
new A.b_(n).cL(m)
s=9
return A.c(new A.ci(m,"message",!1,t.U).gaA(0),$async$$0)
case 9:l=A.oL(n.synchronizationBuffer)
n=n.communicationBuffer
k=A.oO(n,65536,2048)
p=p.Uint8Array
p=t.Z.a(A.cw(p,[n]))
j=A.od("/",$.eV())
i=$.eU()
h=new A.e7(l,new A.aW(n,k,p),j,i,"vfs-web-"+e.b)
e.y=h
e.z=h.gaz()
s=3
break
case 5:s=10
return A.c(A.fU("drift_db/"+e.c,!1,"vfs-web-"+e.b),$async$$0)
case 10:g=b
e.y=g
e.z=g.gaz()
s=3
break
case 6:s=11
return A.c(A.fU("drift_db/"+e.c,!0,"vfs-web-"+e.b),$async$$0)
case 11:g=b
e.y=g
e.z=g.gaz()
s=3
break
case 7:s=12
return A.c(A.fi(e.c,"vfs-web-"+e.b),$async$$0)
case 12:f=b
e.y=f
e.z=f.gaz()
s=3
break
case 8:e.y=A.n3("vfs-web-"+e.b,null)
s=3
break
case 3:return A.h(null,r)}})
return A.i($async$$0,r)},
$S:2}
A.iy.prototype={
$0(){var s=0,r=A.j(t.u),q,p=this,o,n,m,l,k,j,i
var $async$$0=A.k(function(a,b){if(a===1)return A.f(b,r)
for(;;)switch(s){case 0:j=p.a
i=j.a.r
i.toString
s=3
return A.c(i,$async$$0)
case 3:o=b
s=4
return A.c(j.gaD(),$async$$0)
case 4:n=b
i=o.a
i=i.b
m=i.b9(B.h.ac(n.a),1)
l=i.c
k=l.a++
l.e.p(0,k,n)
k=i.d.dart_sqlite3_register_vfs(m,k,0)
if(k===0)A.C(A.L("could not register vfs"))
i=$.nT()
i.a.set(n,k)
s=5
return A.c(j.f.bf(new A.ix(j,o),null,t.u),$async$$0)
case 5:q=b
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$$0,r)},
$S:19}
A.ix.prototype={
$0(){var s=this.a
return s.a.b.aC(this.b,"/database","vfs-web-"+s.b,s.e)},
$S:19}
A.ke.prototype={
aB(){var s=0,r=A.j(t.H),q=1,p=[],o=[],n=this,m,l,k,j,i,h,g,f
var $async$aB=A.k(function(a,b){if(a===1){p.push(b)
s=q}for(;;)switch(s){case 0:g=n.a
f=new A.cp(A.cx(g.gf6(),"stream",t.K))
q=2
i=t.bW
case 5:s=7
return A.c(f.l(),$async$aB)
case 7:if(!b){s=6
break}m=f.gm()
s=m instanceof A.b6?8:10
break
case 8:h=m.c
l=A.pI(h.port,h.lockName,null)
n.dZ(l)
s=9
break
case 10:s=m instanceof A.b_?11:13
break
case 11:s=14
return A.c(A.h6(m.a),$async$aB)
case 14:k=b
i.a(g).a.postMessage(!0)
s=15
return A.c(k.V(),$async$aB)
case 15:s=12
break
case 13:s=m instanceof A.b5?16:17
break
case 16:s=18
return A.c(n.eF(m),$async$aB)
case 18:j=b
i.a(g).a.postMessage(j.gf4())
case 17:case 12:case 9:s=5
break
case 6:o.push(4)
s=3
break
case 2:o=[1]
case 3:q=1
s=19
return A.c(f.B(),$async$aB)
case 19:s=o.pop()
break
case 4:return A.h(null,r)
case 1:return A.f(p.at(-1),r)}})
return A.i($async$aB,r)},
dZ(a){var s,r=this,q=A.ty(a,r.d++,r)
r.c.push(q)
s=q.a.a
s===$&&A.O()
s.c.a.W(new A.kf(r,q))
return q},
eF(a){return this.x.jc(new A.kg(this,a),t.d)},
aq(a){return this.iM(a)},
iM(a){var s=0,r=A.j(t.H),q=this,p,o
var $async$aq=A.k(function(b,c){if(b===1)return A.f(c,r)
for(;;)switch(s){case 0:s=q.r!=null?2:4
break
case 2:if(!J.a_(q.w,a))throw A.a(A.L("Workers only support a single sqlite3 wasm module, provided different URI (has "+A.y(q.w)+", got "+a.i(0)+")"))
p=q.r
s=5
return A.c(t.bU.b(p)?p:A.kP(p,t.aV),$async$aq)
case 5:s=3
break
case 4:o=A.n_(q.b.aq(a),new A.kh(q),t.n,t.K)
q.r=o
s=6
return A.c(o,$async$aq)
case 6:q.w=a
case 3:return A.h(null,r)}})
return A.i($async$aq,r)},
ii(a,b,c){var s,r,q,p
for(s=this.e,r=new A.cM(s,s.r,s.e);r.l();){q=r.d
p=q.r
if(p!==0&&q.c===a&&q.d===b){q.r=p+1
return q}}r=this.f++
q=b===B.Q||b===B.R
q=new A.fa(this,r,a,b,c,new A.iw("pkg-sqlite3-web-"+a,new A.fz(A.ov(t.ge)),q))
s.p(0,r,q)
return q},
f8(){var s=this.z
return s==null?this.z=new v.G.Worker(A.e5().i(0)):s}}
A.kf.prototype={
$0(){return B.c.u(this.a.c,this.b)},
$S:70}
A.kg.prototype={
$0(){var s=0,r=A.j(t.d),q,p=this,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0
var $async$$0=A.k(function(a1,a2){if(a1===1)return A.f(a2,r)
for(;;)switch(s){case 0:c=p.b
b=c.d
c=c.c
o=c!==B.A
s=!o||c===B.y?3:5
break
case 3:s=6
return A.c(A.cy(),$async$$0)
case 6:n=a2
m=n.a
l=n.b
k=l
j=m
s=4
break
case 5:j=!1
k=!1
case 4:a=!o||c===B.o
if(a){s=7
break}else a2=a
s=8
break
case 7:s=9
return A.c(A.mu(),$async$$0)
case 9:case 8:i=a2
h=A.cN(t.ab)
s=c===B.o?10:12
break
case 10:g="Worker" in v.G
s=g?13:14
break
case 13:f=p.a.f8()
new A.b5(B.y,b,0,null).cL(f)
a=A
a0=A
s=15
return A.c(new A.ci(f,"message",!1,t.U).gaA(0),$async$$0)
case 15:e=a.rc(a0.a9(a2.data))
j=e.c
k=e.d
h.am(0,e.a)
case 14:d=g
s=11
break
case 12:d=!1
case 11:s=j?16:17
break
case 16:a=J
s=18
return A.c(A.ds(),$async$$0)
case 18:c=a.ae(a2)
case 19:if(!c.l()){s=20
break}h.E(0,new A.aB(B.af,c.gm()))
s=19
break
case 20:case 17:s=i&&b!=null?21:22
break
case 21:s=23
return A.c(A.ms(b),$async$$0)
case 23:if(a2)h.E(0,new A.aB(B.ag,b))
case 22:c=A.b9(h,h.$ti.c)
o=v.G
q=new A.bR(c,d,j,k,i,"SharedArrayBuffer" in o,"Worker" in o)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$$0,r)},
$S:71}
A.kh.prototype={
$2(a,b){this.a.r=null
throw A.a(a)},
$S:72}
A.jN.prototype={
$1(a){this.a.E(0,a.b)},
$S:29}
A.jK.prototype={
$0(){var s,r,q,p,o,n,m,l,k,j,i
for(s=this.a,r=s.length,q=this.b,p=t.N,o=0;o<s.length;s.length===r||(0,A.R)(s),++o){n=s[o]
n.b.am(0,q)
m=n.a
l=m.b
if((l&1)!==0){k=m.a
j=(((l&8)!==0?k.gbA():k).e&4)!==0
l=j}else l=(l&2)===0
if(!l){l=n.b
if(l.a!==0){j=m.b
if(j>=4)A.C(m.aI())
if((j&1)!==0)m.aL(l)
else if((j&3)===0){m=m.bt()
l=new A.bI(l)
i=m.c
if(i==null)m.b=m.c=l
else{i.saS(l)
m.c=l}}n.b=A.cN(p)}}}q.aw(0)},
$S:0}
A.jL.prototype={
$0(){this.a.aw(0)},
$S:0}
A.jH.prototype={
$1(a){var s,r,q=this,p=q.b
p.push(a)
if(p.length===1){p=q.c
s=p.ex()
r=s.r
s=r==null?s.r=s.eb(!0):r
q.a.a=A.n([s.aQ(q.d),p.d_().gbo().aQ(new A.jI(q.e)),p.d_().gbo().aQ(new A.jJ(q.f))],t.w)}},
$S:32}
A.jI.prototype={
$1(a){return this.a.$0()},
$S:9}
A.jJ.prototype={
$1(a){return this.a.$0()},
$S:9}
A.jO.prototype={
$1(a){var s,r,q=this.b
B.c.u(q,a)
if(q.length===0)for(q=this.a.a,s=q.length,r=0;r<q.length;q.length===s||(0,A.R)(q),++r)q[r].B()},
$S:32}
A.jM.prototype={
$1(a){var s=new A.cq(a,A.cN(t.N))
this.a.$1(s)
a.f=s.gi1()
a.r=new A.jG(this.b,s)},
$S:74}
A.jG.prototype={
$0(){return this.a.$1(this.b)},
$S:0}
A.cq.prototype={
i2(){var s=this.b
if(s.a!==0){this.a.E(0,s)
this.b=A.cN(t.N)}}}
A.bo.prototype={
ae(){return"CustomDatabaseMessageKind."+this.b}}
A.f_.prototype={
aC(a,b,c,d){return this.iS(a,b,c,d)},
iS(a,b,c,d){var s=0,r=A.j(t.u),q,p,o,n
var $async$aC=A.k(function(e,f){if(e===1)return A.f(f,r)
for(;;)switch(s){case 0:p=d==null?null:A.a9(d)
o=a.iR(b,p!=null&&p.useMultipleCiphersVfs?"multipleciphers-"+c:c)
n=A.n([],t.fR)
q=new A.f0(o,A.th(o),new A.jl(n),A.a4(t.fg,t.bD))
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$aC,r)}}
A.f0.prototype={
hw(a,b){var s
if(!a.a){a.a=!0
s=b.a.a
s===$&&A.O()
s.c.a.dO(new A.hS(this,a),t.P)}},
bG(a,b){return this.ir(a,b)},
ir(a,b){var s=0,r=A.j(t.X),q,p=this,o,n,m,l,k,j,i
var $async$bG=A.k(function(c,d){if(c===1)return A.f(d,r)
for(;;)A:switch(s){case 0:A.a9(b)
switch(A.oi(B.b8,b.rawKind).a){case 0:case 4:throw A.a(A.Y("This is a response, not a request"))
case 1:o=p.a.b
q=o.a.d.sqlite3_get_autocommit(o.b)!==0
s=1
break A
case 2:o=b.rawSql
n=A.nj(b.rawParameters,b.typeInfo)
m=p.a
l=m.b
if(l.a.d.sqlite3_get_autocommit(l.b)!==0)throw A.a(A.oQ(0,"Transaction rolled back by earlier statement. Cannot execute: "+o,null,null,null,null,null))
m.eL(o,n)
break
case 3:o=b.rawParameters
k=A.aR(o[0])
o=b.rawSql
j=p.d.eT(a,A.w_())
if(k){j.dQ()
p.hw(j,a)
i=A.pc()
i.b=j.c=p.b.aQ(new A.hT(i,a,o))}else j.dQ()
break}q=A.oe(B.N,null,B.b5)
s=1
break
case 1:return A.h(q,r)}})
return A.i($async$bG,r)}}
A.hS.prototype={
$1(a){this.b.dQ()},
$S:103}
A.hT.prototype={
$1(a){var s=this.a.ej(),r=A.b9(a,a.$ti.c)
s.cu(this.b.c9(A.oe(B.O,this.c,r)))},
$S:76}
A.d6.prototype={
dQ(){var s=this.c
if(s!=null){this.c=null
s.B()}}}
A.dI.prototype={
fu(a,b,c,d){var s=this,r=$.q
s.a!==$&&A.qi()
s.a=new A.hl(a,s,new A.b2(new A.m(r,t.D),t.h),!0)
r=A.jz(null,new A.iQ(c,s),!0,d)
s.b!==$&&A.qi()
s.b=r},
hm(){var s,r
this.d=!0
s=this.c
if(s!=null)s.B()
r=this.b
r===$&&A.O()
r.q()}}
A.iQ.prototype={
$0(){var s,r,q=this.b
if(q.d)return
s=this.a.a
r=q.b
r===$&&A.O()
q.c=s.be(r.gi_(r),new A.iP(q),r.gey())},
$S:0}
A.iP.prototype={
$0(){var s=this.a,r=s.a
r===$&&A.O()
r.hn()
s=s.b
s===$&&A.O()
s.q()},
$S:0}
A.hl.prototype={
E(a,b){if(this.e)throw A.a(A.L("Cannot add event after closing."))
if(this.d)return
this.a.a.E(0,b)},
q(){var s=this
if(s.e)return s.c.a
s.e=!0
if(!s.d){s.b.hm()
s.c.O(s.a.a.q())}return s.c.a},
hn(){this.d=!0
var s=this.c
if((s.a.a&30)===0)s.aN()
return}}
A.fX.prototype={}
A.e2.prototype={$ine:1}
A.d_.prototype={
gk(a){return this.b},
j(a,b){if(b>=this.b)throw A.a(A.ol(b,this))
return this.a[b]},
p(a,b,c){var s
if(b>=this.b)throw A.a(A.ol(b,this))
s=this.a
s.$flags&2&&A.v(s)
s[b]=c},
sk(a,b){var s,r,q,p,o=this,n=o.b
if(b<n)for(s=o.a,r=s.$flags|0,q=b;q<n;++q){r&2&&A.v(s)
s[q]=0}else{n=o.a.length
if(b>n){if(n===0)p=new Uint8Array(b)
else p=o.fQ(b)
B.d.a8(p,0,o.b,o.a)
o.a=p}}o.b=b},
fQ(a){var s=this.a.length*2
if(a!=null&&s<a)s=a
else if(s<8)s=8
return new Uint8Array(s)},
H(a,b,c,d,e){var s=this.b
if(c>s)throw A.a(A.S(c,0,s,null,null))
s=this.a
if(d instanceof A.b1)B.d.H(s,b,c,d.a,e)
else B.d.H(s,b,c,d,e)},
a8(a,b,c,d){return this.H(0,b,c,d,0)}}
A.hp.prototype={}
A.b1.prototype={}
A.jf.prototype={
ff(){var s=this.h_()
if(s.length!==16)throw A.a(A.mX("The length of the Uint8list returned by the custom RNG must be 16."))
else return s}}
A.ie.prototype={
h_(){var s,r,q=new Uint8Array(16)
for(s=0;s<16;s+=4){r=$.qk().bK(B.t.f3(Math.pow(2,32)))
q[s]=r
q[s+1]=B.b.I(r,8)
q[s+2]=B.b.I(r,16)
q[s+3]=B.b.I(r,24)}return q}}
A.jZ.prototype={
f9(){var s,r=null
if(null==null)s=r
else s=r
if(s==null)s=$.qA().ff()
r=s[6]
s.$flags&2&&A.v(s)
s[6]=r&15|64
s[8]=s[8]&63|128
r=s.length
if(r<16)A.C(A.na("buffer too small: need 16: length="+r))
r=$.qz()
return r[s[0]]+r[s[1]]+r[s[2]]+r[s[3]]+"-"+r[s[4]]+r[s[5]]+"-"+r[s[6]]+r[s[7]]+"-"+r[s[8]]+r[s[9]]+"-"+r[s[10]]+r[s[11]]+r[s[12]]+r[s[13]]+r[s[14]]+r[s[15]]}}
A.mW.prototype={}
A.ci.prototype={
U(a,b,c,d){return A.ag(this.a,this.b,a,!1,this.$ti.c)},
be(a,b,c){return this.U(a,null,b,c)}}
A.d9.prototype={
B(){var s=this,r=A.n0(null,t.H)
if(s.b==null)return r
s.dk()
s.d=s.b=null
return r},
eQ(a){var s,r=this
if(r.b==null)throw A.a(A.L("Subscription has been canceled."))
r.dk()
s=A.q2(new A.kM(a),t.m)
s=s==null?null:A.aK(s)
r.d=s
r.di()},
cu(a){var s=this
if(s.b==null)return;++s.a
s.dk()
if(a!=null)a.W(s.gdL())},
ct(){return this.cu(null)},
aU(){var s=this
if(s.b==null||s.a<=0)return;--s.a
s.di()},
di(){var s=this,r=s.d
if(r!=null&&s.a<=0)s.b.addEventListener(s.c,r,!1)},
dk(){var s=this.d
if(s!=null)this.b.removeEventListener(this.c,s,!1)},
$iaH:1}
A.kL.prototype={
$1(a){return this.a.$1(a)},
$S:1}
A.kM.prototype={
$1(a){return this.a.$1(a)},
$S:1};(function aliases(){var s=J.bv.prototype
s.fp=s.i
s=A.bG.prototype
s.fq=s.b3
s.fs=s.bp
s=A.x.prototype
s.dV=s.H
s=A.A.prototype
s.b1=s.G
s=A.cW.prototype
s.ai=s.G
s=A.ak.prototype
s.bT=s.G
s=A.f_.prototype
s.fo=s.aC})();(function installTearOffs(){var s=hunkHelpers._static_2,r=hunkHelpers._static_1,q=hunkHelpers._static_0,p=hunkHelpers._instance_2u,o=hunkHelpers._instance_1i,n=hunkHelpers.installInstanceTearOff,m=hunkHelpers._instance_0u,l=hunkHelpers._instance_1u
s(J,"uw","rB",77)
r(A,"v_","tp",18)
r(A,"v0","tq",18)
r(A,"v1","tr",18)
q(A,"q4","uU",0)
r(A,"v2","uK",6)
s(A,"v4","uM",7)
q(A,"v3","uL",0)
p(A.m.prototype,"ge6","fK",7)
var k
o(k=A.co.prototype,"gi_","E",13)
n(k,"gey",0,1,function(){return[null]},["$2","$1"],["ez","i0"],44,0,0)
m(k=A.d7.prototype,"gdc","b5",0)
m(k,"gdd","b6",0)
m(k=A.bG.prototype,"gdL","aU",0)
m(k,"gdc","b5",0)
m(k,"gdd","b6",0)
l(k=A.cp.prototype,"ghg","hh",13)
p(k,"ghk","hl",7)
m(k,"ghi","hj",0)
m(k=A.da.prototype,"gdc","b5",0)
m(k,"gdd","b6",0)
l(k,"gh1","h2",13)
p(k,"gh6","h7",46)
m(k,"gh4","h5",0)
r(A,"v7","um",33)
r(A,"v8","tm",79)
m(A.e7.prototype,"gaz","q",0)
r(A,"bk","rJ",80)
r(A,"aL","rK",81)
r(A,"nS","rL",82)
l(A.e6.prototype,"ghx","hy",38)
m(A.f1.prototype,"gaz","q",0)
m(A.bY.prototype,"gaz","q",2)
m(A.cj.prototype,"gcz","R",0)
m(A.d8.prototype,"gcz","R",2)
m(A.cg.prototype,"gcz","R",2)
m(A.cs.prototype,"gcz","R",2)
m(A.cY.prototype,"gaz","q",0)
l(A.fN.prototype,"gh8","bX",27)
m(A.bt.prototype,"giZ","j_",0)
r(A,"qd","rN",34)
r(A,"vH","rR",34)
r(A,"vI","rS",10)
r(A,"vG","rQ",10)
r(A,"vD","rM",10)
r(A,"vF","rP",20)
r(A,"vE","rO",20)
r(A,"vK","rW",86)
r(A,"vw","rg",87)
r(A,"vQ","te",88)
r(A,"vx","rh",89)
r(A,"vB","rt",90)
r(A,"vC","ru",91)
r(A,"vA","rr",92)
r(A,"vO","tb",93)
r(A,"vM","t6",94)
r(A,"vL","t5",95)
r(A,"vv","r6",96)
r(A,"vJ","rV",97)
r(A,"vP","tc",98)
r(A,"vy","rj",99)
r(A,"vN","t7",100)
r(A,"vz","rm",101)
r(A,"vR","ti",102)
r(A,"vu","r1",75)
m(A.cq.prototype,"gi1","i2",0)
q(A,"w_","tz",69)
m(A.d9.prototype,"gdL","aU",0)})();(function inheritance(){var s=hunkHelpers.mixin,r=hunkHelpers.inherit,q=hunkHelpers.inheritMany
r(A.l,null)
q(A.l,[A.n4,J.fl,A.dY,J.cG,A.d,A.f5,A.G,A.x,A.bQ,A.jo,A.cO,A.fy,A.e9,A.fV,A.fd,A.h9,A.dG,A.h0,A.eu,A.dz,A.hs,A.jP,A.fI,A.dE,A.ey,A.N,A.j0,A.fx,A.cM,A.fw,A.fr,A.en,A.ki,A.fY,A.m4,A.he,A.hH,A.aP,A.hk,A.m7,A.m5,A.eb,A.hF,A.T,A.d4,A.b3,A.m,A.hb,A.a1,A.co,A.hG,A.hc,A.bG,A.eA,A.hg,A.kJ,A.et,A.cp,A.me,A.hm,A.cX,A.lS,A.dc,A.ht,A.am,A.hu,A.f7,A.bS,A.lQ,A.mc,A.eK,A.U,A.hj,A.dB,A.dC,A.kK,A.fJ,A.e0,A.hi,A.aV,A.fk,A.ao,A.B,A.hE,A.ab,A.eH,A.jU,A.aI,A.fe,A.fH,A.lM,A.lN,A.fG,A.h1,A.jl,A.f9,A.de,A.df,A.jE,A.ja,A.dV,A.ii,A.aG,A.ca,A.cF,A.jg,A.fW,A.jh,A.jj,A.ji,A.cT,A.cU,A.b7,A.ij,A.bJ,A.jw,A.i1,A.bf,A.f3,A.ig,A.hA,A.lW,A.fj,A.aq,A.dZ,A.ch,A.jn,A.aW,A.bb,A.hx,A.e6,A.dd,A.f1,A.kN,A.hv,A.ho,A.h7,A.l1,A.ih,A.fP,A.jm,A.cf,A.k9,A.bt,A.iw,A.fz,A.A,A.bR,A.cV,A.kd,A.eB,A.d5,A.fa,A.ke,A.cq,A.d6,A.e2,A.hl,A.fX,A.jf,A.jZ,A.mW,A.d9])
q(J.fl,[J.fo,J.dL,J.P,J.ai,J.cL,J.cK,J.bu])
q(J.P,[J.bv,J.t,A.cP,A.dR])
q(J.bv,[J.fL,J.ce,J.ax])
r(J.fn,A.dY)
r(J.iY,J.t)
q(J.cK,[J.dK,J.fp])
q(A.d,[A.bH,A.p,A.ba,A.e8,A.bc,A.ea,A.el,A.ha,A.hD,A.dg,A.dO])
q(A.bH,[A.bN,A.eL])
r(A.eh,A.bN)
r(A.ee,A.eL)
r(A.bO,A.ee)
q(A.G,[A.c_,A.bd,A.fs,A.h_,A.fR,A.hh,A.dM,A.eY,A.aN,A.e4,A.fZ,A.b0,A.f8])
q(A.x,[A.d0,A.h5,A.d3,A.d_])
r(A.f6,A.d0)
q(A.bQ,[A.i_,A.i0,A.jF,A.mB,A.mD,A.kk,A.kj,A.mf,A.iN,A.kZ,A.jC,A.jB,A.lZ,A.j2,A.kp,A.iI,A.mF,A.mJ,A.mK,A.mw,A.ic,A.id,A.mq,A.mL,A.mM,A.mN,A.mO,A.mP,A.jx,A.is,A.m1,A.my,A.hR,A.kH,A.kI,A.i4,A.i5,A.i9,A.ia,A.ib,A.iD,A.hX,A.hU,A.hV,A.jv,A.lh,A.li,A.lj,A.lu,A.lF,A.lG,A.lJ,A.lK,A.lL,A.lk,A.lr,A.ls,A.lt,A.lv,A.lw,A.lx,A.ly,A.lz,A.lA,A.lB,A.lE,A.mi,A.mj,A.ml,A.je,A.ka,A.j6,A.iC,A.mt,A.i2,A.i3,A.i6,A.i7,A.i8,A.iA,A.jt,A.ju,A.js,A.jq,A.ky,A.kx,A.kw,A.kt,A.jN,A.jH,A.jI,A.jJ,A.jO,A.jM,A.hS,A.hT,A.kL,A.kM])
q(A.i_,[A.mH,A.kl,A.km,A.m6,A.iM,A.iL,A.kQ,A.kV,A.kU,A.kS,A.kR,A.kY,A.kX,A.kW,A.jD,A.jA,A.m0,A.m_,A.kr,A.kq,A.lU,A.lT,A.mh,A.lY,A.mp,A.mb,A.ma,A.it,A.iu,A.iq,A.ip,A.ir,A.il,A.ik,A.im,A.io,A.m2,A.m3,A.hP,A.hQ,A.hY,A.kO,A.iR,A.iS,A.l0,A.l8,A.l7,A.l6,A.l5,A.lg,A.lf,A.le,A.ld,A.lc,A.lb,A.la,A.l9,A.l4,A.l3,A.l2,A.mk,A.j8,A.j7,A.jr,A.kC,A.kG,A.kD,A.kF,A.ku,A.kv,A.kz,A.kA,A.kB,A.iz,A.iy,A.ix,A.kf,A.kg,A.jK,A.jL,A.jG,A.iQ,A.iP])
q(A.p,[A.a7,A.bU,A.b8,A.dN,A.ek])
q(A.a7,[A.cc,A.aa,A.dX,A.dP,A.hr])
r(A.bT,A.ba)
r(A.cH,A.bc)
r(A.hw,A.eu)
q(A.hw,[A.aB,A.ev,A.ew,A.cn])
r(A.dA,A.dz)
r(A.dU,A.bd)
q(A.jF,[A.jy,A.dw])
q(A.N,[A.bZ,A.ej,A.hq])
q(A.i0,[A.iZ,A.mC,A.mg,A.mr,A.iO,A.iH,A.l_,A.j3,A.lR,A.ko,A.jW,A.iK,A.iJ,A.iv,A.k3,A.k2,A.hW,A.lH,A.lI,A.ll,A.lm,A.ln,A.lo,A.lp,A.lq,A.lC,A.lD,A.kb,A.j5,A.j4,A.kE,A.kh])
r(A.c1,A.cP)
q(A.dR,[A.c2,A.cR])
q(A.cR,[A.ep,A.er])
r(A.eq,A.ep)
r(A.bx,A.eq)
r(A.es,A.er)
r(A.aA,A.es)
q(A.bx,[A.fA,A.fB])
q(A.aA,[A.fC,A.cQ,A.fD,A.fE,A.fF,A.dS,A.c3])
r(A.eC,A.hh)
q(A.d4,[A.b2,A.H])
q(A.co,[A.bF,A.dh])
q(A.a1,[A.ez,A.bh,A.ei,A.dv,A.ci])
r(A.as,A.ez)
q(A.bG,[A.d7,A.da])
q(A.hg,[A.bI,A.eg])
r(A.eo,A.bF)
r(A.cl,A.ei)
r(A.lX,A.me)
r(A.db,A.ej)
r(A.ex,A.cX)
r(A.em,A.ex)
q(A.f7,[A.hZ,A.iB,A.j_])
q(A.bS,[A.f2,A.fv,A.fu,A.h4])
r(A.ft,A.dM)
r(A.lP,A.lQ)
r(A.jY,A.iB)
q(A.aN,[A.cS,A.dJ])
r(A.hf,A.eH)
r(A.iW,A.jE)
q(A.iW,[A.jb,A.jX,A.kc])
r(A.f_,A.ii)
r(A.jc,A.f_)
q(A.kK,[A.cZ,A.j9,A.Z,A.cI,A.w,A.bs,A.aQ,A.dF,A.bz,A.bo])
q(A.b7,[A.ff,A.cJ])
r(A.e1,A.i1)
r(A.f4,A.bf)
q(A.f4,[A.fg,A.e7,A.bY,A.cY])
q(A.f3,[A.hn,A.h8,A.hC])
r(A.hy,A.ig)
r(A.hz,A.hy)
r(A.fQ,A.hz)
r(A.hB,A.hA)
r(A.aY,A.hB)
r(A.k6,A.jg)
r(A.k0,A.jh)
r(A.k8,A.jj)
r(A.k7,A.ji)
r(A.bD,A.cT)
r(A.bg,A.cU)
r(A.d2,A.jw)
q(A.bb,[A.aE,A.J])
r(A.az,A.J)
r(A.a8,A.am)
q(A.a8,[A.cj,A.d8,A.cg,A.cs])
r(A.fN,A.jm)
q(A.A,[A.dT,A.cW,A.ak,A.b_,A.bn])
q(A.cW,[A.c5,A.b6,A.bp,A.bW,A.bX,A.bV,A.c9,A.c8,A.c7,A.bP,A.c4,A.cb,A.b5])
q(A.ak,[A.X,A.bq,A.aZ,A.br])
q(A.dT,[A.bB,A.aU])
r(A.bm,A.cV)
q(A.kd,[A.fc,A.jp])
r(A.ef,A.fN)
r(A.f0,A.cf)
r(A.dI,A.e2)
r(A.hp,A.d_)
r(A.b1,A.hp)
r(A.ie,A.jf)
s(A.d0,A.h0)
s(A.eL,A.x)
s(A.ep,A.x)
s(A.eq,A.dG)
s(A.er,A.x)
s(A.es,A.dG)
s(A.bF,A.hc)
s(A.dh,A.hG)
s(A.hy,A.x)
s(A.hz,A.fG)
s(A.hA,A.h1)
s(A.hB,A.N)})()
var v={G:typeof self!="undefined"?self:globalThis,typeUniverse:{eC:new Map(),tR:{},eT:{},tPV:{},sEA:[]},mangledGlobalNames:{b:"int",I:"double",qb:"num",o:"String",ad:"bool",B:"Null",u:"List",l:"Object",af:"Map",e:"JSObject"},mangledNames:{},types:["~()","~(e)","K<~>()","b(b,b)","B()","B(b)","~(@)","~(l,a0)","o(e_)","~(~)","cb(e)","B(@)","B(l,a0)","~(l?)","b(b)","B(e)","b(b,b,b)","B(b,b,b)","~(~())","K<cf>()","aU(e)","l?(l?)","ad(o)","b(b,b,b,b)","b(b,b,b,b,b)","b(b,b,b,ai)","~(l?,l?)","~(A)","~(l?,e)","~(aG)","K<aH<~>>()","@()","~(cq)","@(@)","b5(e)","@(@,o)","~(o,af<o,l?>)","~(o,l?)","~(dd)","e(e?)","K<~>(b,cd)","K<~>(b)","cd()","K<e>(o)","~(l[a0?])","l?(~)","~(@,a0)","0&(o,b?)","B(b,b)","o(o?)","b(b,ai)","~(b,@)","e(t<l?>)","b?(b)","B(ai,b)","b(e_)","B(bt)","e(l)","B(l?,a0)","o(l?)","o?(l?)","A(e)","~(c0<A>)","aZ()","K<aH<aG>>()","~(b,o,b)","b()","~(cT,u<cU>)","ad(d5)","d6()","ad()","K<bR>()","0&(l?,a0)","~(b7)","~(c0<by<o>>)","bn(e)","~(by<o>)","b(@,@)","B(~())","o(o)","aE(aW)","J(aW)","az(aW)","B(ax,ax)","B(@,a0)","@(o)","c5(e)","b6(e)","b_(e)","bp(e)","bW(e)","bX(e)","bV(e)","c9(e)","c8(e)","c7(e)","bP(e)","c4(e)","X(e)","bq(e)","aZ(e)","br(e)","bB(e)","B(~)","B(b,b,b,b,ai)"],interceptorsByTag:null,leafTags:null,arrayRti:Symbol("$ti"),rttc:{"2;":(a,b)=>c=>c instanceof A.aB&&a.b(c.a)&&b.b(c.b),"2;basicSupport,supportsReadWriteUnsafe":(a,b)=>c=>c instanceof A.ev&&a.b(c.a)&&b.b(c.b),"2;controller,sync":(a,b)=>c=>c instanceof A.ew&&a.b(c.a)&&b.b(c.b),"2;file,outFlags":(a,b)=>c=>c instanceof A.cn&&a.b(c.a)&&b.b(c.b)}}
A.tT(v.typeUniverse,JSON.parse('{"ax":"bv","fL":"bv","ce":"bv","wb":"cP","t":{"u":["1"],"P":[],"p":["1"],"e":[],"d":["1"]},"fo":{"ad":[],"F":[]},"dL":{"B":[],"F":[]},"P":{"e":[]},"bv":{"P":[],"e":[]},"fn":{"dY":[]},"iY":{"t":["1"],"u":["1"],"P":[],"p":["1"],"e":[],"d":["1"]},"cK":{"I":[]},"dK":{"I":[],"b":[],"F":[]},"fp":{"I":[],"F":[]},"bu":{"o":[],"F":[]},"bH":{"d":["2"]},"bN":{"bH":["1","2"],"d":["2"],"d.E":"2"},"eh":{"bN":["1","2"],"bH":["1","2"],"p":["2"],"d":["2"],"d.E":"2"},"ee":{"x":["2"],"u":["2"],"bH":["1","2"],"p":["2"],"d":["2"]},"bO":{"ee":["1","2"],"x":["2"],"u":["2"],"bH":["1","2"],"p":["2"],"d":["2"],"x.E":"2","d.E":"2"},"c_":{"G":[]},"f6":{"x":["b"],"u":["b"],"p":["b"],"d":["b"],"x.E":"b"},"p":{"d":["1"]},"a7":{"p":["1"],"d":["1"]},"cc":{"a7":["1"],"p":["1"],"d":["1"],"a7.E":"1","d.E":"1"},"ba":{"d":["2"],"d.E":"2"},"bT":{"ba":["1","2"],"p":["2"],"d":["2"],"d.E":"2"},"aa":{"a7":["2"],"p":["2"],"d":["2"],"a7.E":"2","d.E":"2"},"e8":{"d":["1"],"d.E":"1"},"bc":{"d":["1"],"d.E":"1"},"cH":{"bc":["1"],"p":["1"],"d":["1"],"d.E":"1"},"bU":{"p":["1"],"d":["1"],"d.E":"1"},"ea":{"d":["1"],"d.E":"1"},"d0":{"x":["1"],"u":["1"],"p":["1"],"d":["1"]},"dX":{"a7":["1"],"p":["1"],"d":["1"],"a7.E":"1","d.E":"1"},"dz":{"af":["1","2"]},"dA":{"dz":["1","2"],"af":["1","2"]},"el":{"d":["1"],"d.E":"1"},"dU":{"bd":[],"G":[]},"fs":{"G":[]},"h_":{"G":[]},"fI":{"a6":[]},"ey":{"a0":[]},"fR":{"G":[]},"bZ":{"N":["1","2"],"af":["1","2"],"N.V":"2","N.K":"1"},"b8":{"p":["1"],"d":["1"],"d.E":"1"},"dN":{"p":["ao<1,2>"],"d":["ao<1,2>"],"d.E":"ao<1,2>"},"en":{"fO":[],"dQ":[]},"ha":{"d":["fO"],"d.E":"fO"},"fY":{"dQ":[]},"hD":{"d":["dQ"],"d.E":"dQ"},"c1":{"P":[],"e":[],"dx":[],"F":[]},"c2":{"P":[],"mV":[],"e":[],"F":[]},"cQ":{"aA":[],"iU":[],"x":["b"],"u":["b"],"ay":["b"],"P":[],"p":["b"],"e":[],"d":["b"],"F":[],"x.E":"b"},"c3":{"aA":[],"cd":[],"x":["b"],"u":["b"],"ay":["b"],"P":[],"p":["b"],"e":[],"d":["b"],"F":[],"x.E":"b"},"cP":{"P":[],"e":[],"dx":[],"F":[]},"dR":{"P":[],"e":[]},"hH":{"dx":[]},"cR":{"ay":["1"],"P":[],"e":[]},"bx":{"x":["I"],"u":["I"],"ay":["I"],"P":[],"p":["I"],"e":[],"d":["I"]},"aA":{"x":["b"],"u":["b"],"ay":["b"],"P":[],"p":["b"],"e":[],"d":["b"]},"fA":{"bx":[],"iF":[],"x":["I"],"u":["I"],"ay":["I"],"P":[],"p":["I"],"e":[],"d":["I"],"F":[],"x.E":"I"},"fB":{"bx":[],"iG":[],"x":["I"],"u":["I"],"ay":["I"],"P":[],"p":["I"],"e":[],"d":["I"],"F":[],"x.E":"I"},"fC":{"aA":[],"iT":[],"x":["b"],"u":["b"],"ay":["b"],"P":[],"p":["b"],"e":[],"d":["b"],"F":[],"x.E":"b"},"fD":{"aA":[],"iV":[],"x":["b"],"u":["b"],"ay":["b"],"P":[],"p":["b"],"e":[],"d":["b"],"F":[],"x.E":"b"},"fE":{"aA":[],"jR":[],"x":["b"],"u":["b"],"ay":["b"],"P":[],"p":["b"],"e":[],"d":["b"],"F":[],"x.E":"b"},"fF":{"aA":[],"jS":[],"x":["b"],"u":["b"],"ay":["b"],"P":[],"p":["b"],"e":[],"d":["b"],"F":[],"x.E":"b"},"dS":{"aA":[],"jT":[],"x":["b"],"u":["b"],"ay":["b"],"P":[],"p":["b"],"e":[],"d":["b"],"F":[],"x.E":"b"},"hh":{"G":[]},"eC":{"bd":[],"G":[]},"eb":{"dy":["1"]},"dg":{"d":["1"],"d.E":"1"},"T":{"G":[]},"d4":{"dy":["1"]},"b2":{"d4":["1"],"dy":["1"]},"H":{"d4":["1"],"dy":["1"]},"m":{"K":["1"]},"bF":{"co":["1"]},"dh":{"co":["1"]},"as":{"ez":["1"],"a1":["1"],"a1.T":"1"},"d7":{"bG":["1"],"aH":["1"]},"bG":{"aH":["1"]},"ez":{"a1":["1"]},"bh":{"a1":["1"],"a1.T":"1"},"eo":{"bF":["1"],"co":["1"],"c0":["1"]},"ei":{"a1":["2"]},"da":{"bG":["2"],"aH":["2"]},"cl":{"ei":["1","2"],"a1":["2"],"a1.T":"2"},"ej":{"N":["1","2"],"af":["1","2"]},"db":{"ej":["1","2"],"N":["1","2"],"af":["1","2"],"N.V":"2","N.K":"1"},"ek":{"p":["1"],"d":["1"],"d.E":"1"},"em":{"cX":["1"],"by":["1"],"p":["1"],"d":["1"]},"dO":{"d":["1"],"d.E":"1"},"x":{"u":["1"],"p":["1"],"d":["1"]},"N":{"af":["1","2"]},"dP":{"a7":["1"],"p":["1"],"d":["1"],"a7.E":"1","d.E":"1"},"cX":{"by":["1"],"p":["1"],"d":["1"]},"ex":{"cX":["1"],"by":["1"],"p":["1"],"d":["1"]},"hq":{"N":["o","@"],"af":["o","@"],"N.V":"@","N.K":"o"},"hr":{"a7":["o"],"p":["o"],"d":["o"],"a7.E":"o","d.E":"o"},"f2":{"bS":["u<b>","o"]},"dM":{"G":[]},"ft":{"G":[]},"fv":{"bS":["l?","o"]},"fu":{"bS":["o","l?"]},"h4":{"bS":["o","u<b>"]},"u":{"p":["1"],"d":["1"]},"fO":{"dQ":[]},"by":{"p":["1"],"d":["1"]},"eY":{"G":[]},"bd":{"G":[]},"aN":{"G":[]},"cS":{"G":[]},"dJ":{"G":[]},"e4":{"G":[]},"fZ":{"G":[]},"b0":{"G":[]},"f8":{"G":[]},"fJ":{"G":[]},"e0":{"G":[]},"hi":{"a6":[]},"aV":{"a6":[]},"fk":{"a6":[],"G":[]},"hE":{"a0":[]},"eH":{"h2":[]},"aI":{"h2":[]},"hf":{"h2":[]},"fH":{"a6":[]},"dV":{"a6":[]},"ca":{"a6":[]},"e_":{"u":["l?"],"p":["l?"],"d":["l?"]},"ff":{"b7":[]},"h5":{"x":["l?"],"e_":[],"u":["l?"],"p":["l?"],"d":["l?"],"x.E":"l?"},"cJ":{"b7":[]},"fg":{"bf":[]},"hn":{"d1":[]},"aY":{"N":["o","@"],"af":["o","@"],"N.V":"@","N.K":"o"},"fQ":{"x":["aY"],"u":["aY"],"p":["aY"],"d":["aY"],"x.E":"aY"},"aq":{"a6":[]},"f4":{"bf":[]},"f3":{"d1":[]},"bg":{"cU":[]},"bD":{"cT":[]},"d3":{"x":["bg"],"u":["bg"],"p":["bg"],"d":["bg"],"x.E":"bg"},"dv":{"a1":["1"],"a1.T":"1"},"e7":{"bf":[]},"h8":{"d1":[]},"aE":{"bb":[]},"J":{"bb":[]},"az":{"J":[],"bb":[]},"bY":{"bf":[]},"a8":{"am":["a8"]},"ho":{"d1":[]},"cj":{"a8":[],"am":["a8"],"am.E":"a8"},"d8":{"a8":[],"am":["a8"],"am.E":"a8"},"cg":{"a8":[],"am":["a8"],"am.E":"a8"},"cs":{"a8":[],"am":["a8"],"am.E":"a8"},"cY":{"bf":[]},"hC":{"d1":[]},"ak":{"A":[]},"c5":{"A":[]},"b6":{"A":[]},"b_":{"A":[]},"bp":{"A":[]},"bW":{"A":[]},"bX":{"A":[]},"bV":{"A":[]},"c9":{"A":[]},"c8":{"A":[]},"c7":{"A":[]},"bP":{"A":[]},"c4":{"A":[]},"X":{"ak":[],"A":[]},"bq":{"ak":[],"A":[]},"aZ":{"ak":[],"A":[]},"br":{"ak":[],"A":[]},"cb":{"A":[]},"b5":{"A":[]},"bB":{"A":[]},"aU":{"A":[]},"bn":{"A":[]},"dT":{"A":[]},"cW":{"A":[]},"cV":{"a6":[]},"bm":{"a6":[]},"ef":{"oa":[]},"f0":{"cf":[]},"dI":{"ne":["1"]},"e2":{"ne":["1"]},"b1":{"d_":["b"],"x":["b"],"u":["b"],"p":["b"],"d":["b"],"x.E":"b"},"d_":{"x":["1"],"u":["1"],"p":["1"],"d":["1"]},"hp":{"d_":["b"],"x":["b"],"u":["b"],"p":["b"],"d":["b"]},"ci":{"a1":["1"],"a1.T":"1"},"d9":{"aH":["1"]},"iV":{"u":["b"],"p":["b"],"d":["b"]},"cd":{"u":["b"],"p":["b"],"d":["b"]},"jT":{"u":["b"],"p":["b"],"d":["b"]},"iT":{"u":["b"],"p":["b"],"d":["b"]},"jR":{"u":["b"],"p":["b"],"d":["b"]},"iU":{"u":["b"],"p":["b"],"d":["b"]},"jS":{"u":["b"],"p":["b"],"d":["b"]},"iF":{"u":["I"],"p":["I"],"d":["I"]},"iG":{"u":["I"],"p":["I"],"d":["I"]}}'))
A.tS(v.typeUniverse,JSON.parse('{"e9":1,"fV":1,"fd":1,"dG":1,"h0":1,"d0":1,"eL":2,"fx":1,"cM":1,"cR":1,"hF":1,"hG":1,"hc":1,"eA":1,"hg":1,"bI":1,"et":1,"cp":1,"ex":1,"f7":2,"fe":1,"fG":1,"h1":2,"r2":1,"fW":1,"hl":1,"e2":1}'))
var u={v:"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\u03f6\x00\u0404\u03f4 \u03f4\u03f6\u01f6\u01f6\u03f6\u03fc\u01f4\u03ff\u03ff\u0584\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u05d4\u01f4\x00\u01f4\x00\u0504\u05c4\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u0400\x00\u0400\u0200\u03f7\u0200\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u03ff\u0200\u0200\u0200\u03f7\x00",l:"Cannot extract a file path from a URI with a fragment component",y:"Cannot extract a file path from a URI with a query component",j:"Cannot extract a non-Windows file path from a file URI with an authority",c:"Error handler must accept one Object or one Object and a StackTrace as arguments, and return a value of the returned future's type",D:"Tried to operate on a released prepared statement",w:"max must be in range 0 < max \u2264 2^32, was "}
var t=(function rtii(){var s=A.E
return{b9:s("r2<l?>"),cO:s("dv<t<l?>>"),J:s("dx"),fd:s("mV"),fg:s("oa"),d:s("bR"),eR:s("dy<ak>"),eX:s("fa"),bW:s("fc"),O:s("p<@>"),r:s("aE"),C:s("G"),g8:s("a6"),v:s("cI"),f:s("J"),h4:s("iF"),gN:s("iG"),b8:s("w7"),gy:s("K<ak>"),bU:s("K<d2?>"),bd:s("bY"),dQ:s("iT"),an:s("iU"),gj:s("iV"),hf:s("d<@>"),eV:s("t<cJ>"),M:s("t<K<~>>"),fk:s("t<t<l?>>"),W:s("t<e>"),E:s("t<u<l?>>"),fS:s("t<+controller,sync(c0<aG>,ad)>"),e:s("t<+controller,sync(c0<~>,ad)>"),gQ:s("t<+(bz,o)>"),bb:s("t<e1>"),db:s("t<aH<@>>"),w:s("t<aH<~>>"),s:s("t<o>"),bj:s("t<ef>"),bZ:s("t<d5>"),f6:s("t<hv>"),fR:s("t<wH>"),ey:s("t<cq>"),B:s("t<I>"),gn:s("t<@>"),t:s("t<b>"),c:s("t<l?>"),G:s("t<o?>"),bT:s("t<~()>"),T:s("dL"),m:s("e"),fV:s("ai"),g:s("ax"),aU:s("ay<@>"),aX:s("P"),au:s("dO<a8>"),cl:s("u<e>"),Y:s("u<o>"),j:s("u<@>"),L:s("u<b>"),dY:s("af<o,e>"),d1:s("af<o,@>"),g6:s("af<o,b>"),_:s("af<@,@>"),do:s("aa<o,@>"),gR:s("bb"),x:s("w<b5>"),dh:s("w<aU>"),b:s("w<cb>"),cb:s("A"),eN:s("az"),a:s("c1"),gT:s("c2"),ha:s("cQ"),d4:s("bx"),eB:s("aA"),Z:s("c3"),P:s("B"),K:s("l"),fl:s("wd"),bQ:s("+()"),dX:s("+(e,ne<A>)"),ab:s("+(bz,o)"),f9:s("+(ad,e)"),c9:s("+basicSupport,supportsReadWriteUnsafe(ad,ad)"),cf:s("+(e?,e)"),cV:s("+(l?,b)"),cz:s("fO"),dG:s("fP"),q:s("ak"),bJ:s("dX<o>"),dW:s("we"),gW:s("cY"),cs:s("X"),gm:s("a0"),gl:s("fX<A>"),aY:s("aH<aG>"),fY:s("aH<~>"),N:s("o"),dm:s("F"),eK:s("bd"),h7:s("jR"),bv:s("jS"),go:s("jT"),p:s("cd"),ak:s("ce"),dD:s("h2"),ei:s("e6"),l:s("bf"),cG:s("d1"),h2:s("h7"),n:s("d2"),eJ:s("ea<o>"),u:s("cf"),R:s("Z<J,aE>"),dx:s("Z<J,J>"),b0:s("Z<az,J>"),bS:s("b2<b>"),h:s("b2<~>"),bD:s("d6"),Q:s("ch<e>"),U:s("ci<e>"),cp:s("m<bt>"),et:s("m<e>"),fO:s("m<ak>"),k:s("m<ad>"),eI:s("m<@>"),fJ:s("m<b>"),D:s("m<~>"),hg:s("db<l?,l?>"),dZ:s("bh<A>"),aT:s("bh<by<o>>"),cT:s("dd"),eg:s("hx"),fs:s("bJ<aG,~()>"),fK:s("bJ<~,ad()>"),bq:s("bJ<~,~()>"),eP:s("H<bt>"),eC:s("H<e>"),ex:s("H<ak>"),fa:s("H<ad>"),F:s("H<~>"),y:s("ad"),i:s("I"),z:s("@"),bI:s("@(l)"),V:s("@(l,a0)"),S:s("b"),eH:s("K<B>?"),A:s("e?"),dy:s("c1?"),X:s("l?"),dk:s("o?"),fN:s("b1?"),aV:s("d2?"),fQ:s("ad?"),cD:s("I?"),I:s("b?"),cg:s("qb?"),o:s("qb"),H:s("~"),ge:s("~()"),d5:s("~(l)"),da:s("~(l,a0)")}})();(function constants(){var s=hunkHelpers.makeConstList
B.b_=J.fl.prototype
B.c=J.t.prototype
B.b=J.dK.prototype
B.t=J.cK.prototype
B.a=J.bu.prototype
B.b0=J.ax.prototype
B.b1=J.P.prototype
B.bc=A.c2.prototype
B.d=A.c3.prototype
B.ab=J.fL.prototype
B.E=J.ce.prototype
B.K=new A.bm("Operation was cancelled")
B.p=new A.cF(0)
B.aD=new A.cF(1)
B.aE=new A.cF(2)
B.by=new A.cF(-1)
B.bz=new A.f2()
B.aF=new A.hZ()
B.aG=new A.fd()
B.f=new A.aE()
B.aH=new A.fk()
B.L=function getTagFallback(o) {
  var s = Object.prototype.toString.call(o);
  return s.substring(8, s.length - 1);
}
B.aI=function() {
  var toStringFunction = Object.prototype.toString;
  function getTag(o) {
    var s = toStringFunction.call(o);
    return s.substring(8, s.length - 1);
  }
  function getUnknownTag(object, tag) {
    if (/^HTML[A-Z].*Element$/.test(tag)) {
      var name = toStringFunction.call(object);
      if (name == "[object Object]") return null;
      return "HTMLElement";
    }
  }
  function getUnknownTagGenericBrowser(object, tag) {
    if (object instanceof HTMLElement) return "HTMLElement";
    return getUnknownTag(object, tag);
  }
  function prototypeForTag(tag) {
    if (typeof window == "undefined") return null;
    if (typeof window[tag] == "undefined") return null;
    var constructor = window[tag];
    if (typeof constructor != "function") return null;
    return constructor.prototype;
  }
  function discriminator(tag) { return null; }
  var isBrowser = typeof HTMLElement == "function";
  return {
    getTag: getTag,
    getUnknownTag: isBrowser ? getUnknownTagGenericBrowser : getUnknownTag,
    prototypeForTag: prototypeForTag,
    discriminator: discriminator };
}
B.aN=function(getTagFallback) {
  return function(hooks) {
    if (typeof navigator != "object") return hooks;
    var userAgent = navigator.userAgent;
    if (typeof userAgent != "string") return hooks;
    if (userAgent.indexOf("DumpRenderTree") >= 0) return hooks;
    if (userAgent.indexOf("Chrome") >= 0) {
      function confirm(p) {
        return typeof window == "object" && window[p] && window[p].name == p;
      }
      if (confirm("Window") && confirm("HTMLElement")) return hooks;
    }
    hooks.getTag = getTagFallback;
  };
}
B.aJ=function(hooks) {
  if (typeof dartExperimentalFixupGetTag != "function") return hooks;
  hooks.getTag = dartExperimentalFixupGetTag(hooks.getTag);
}
B.aM=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Firefox") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "GeoGeolocation": "Geolocation",
    "Location": "!Location",
    "WorkerMessageEvent": "MessageEvent",
    "XMLDocument": "!Document"};
  function getTagFirefox(o) {
    var tag = getTag(o);
    return quickMap[tag] || tag;
  }
  hooks.getTag = getTagFirefox;
}
B.aL=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Trident/") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "HTMLDDElement": "HTMLElement",
    "HTMLDTElement": "HTMLElement",
    "HTMLPhraseElement": "HTMLElement",
    "Position": "Geoposition"
  };
  function getTagIE(o) {
    var tag = getTag(o);
    var newTag = quickMap[tag];
    if (newTag) return newTag;
    if (tag == "Object") {
      if (window.DataView && (o instanceof window.DataView)) return "DataView";
    }
    return tag;
  }
  function prototypeForTagIE(tag) {
    var constructor = window[tag];
    if (constructor == null) return null;
    return constructor.prototype;
  }
  hooks.getTag = getTagIE;
  hooks.prototypeForTag = prototypeForTagIE;
}
B.aK=function(hooks) {
  var getTag = hooks.getTag;
  var prototypeForTag = hooks.prototypeForTag;
  function getTagFixed(o) {
    var tag = getTag(o);
    if (tag == "Document") {
      if (!!o.xmlVersion) return "!Document";
      return "!HTMLDocument";
    }
    return tag;
  }
  function prototypeForTagFixed(tag) {
    if (tag == "Document") return null;
    return prototypeForTag(tag);
  }
  hooks.getTag = getTagFixed;
  hooks.prototypeForTag = prototypeForTagFixed;
}
B.M=function(hooks) { return hooks; }

B.q=new A.j_()
B.aO=new A.fJ()
B.k=new A.jo()
B.m=new A.jY()
B.h=new A.h4()
B.r=new A.kJ()
B.aP=new A.lM()
B.e=new A.lX()
B.n=new A.hE()
B.N=new A.bo(0,"ok")
B.O=new A.bo(4,"notifyUpdates")
B.P=new A.dC(0)
B.Q=new A.bs("l",1,"opfsAtomics")
B.R=new A.bs("x",2,"opfsExternalLocks")
B.b2=new A.fu(null)
B.b3=new A.fv(null)
B.l=new A.aQ(0,"unknown")
B.ah=new A.aQ(1,"integer")
B.ai=new A.aQ(2,"bigInt")
B.aj=new A.aQ(3,"float")
B.ak=new A.aQ(4,"text")
B.al=new A.aQ(5,"blob")
B.am=new A.aQ(6,"$null")
B.an=new A.aQ(7,"boolean")
B.S=s([B.l,B.ah,B.ai,B.aj,B.ak,B.al,B.am,B.an],A.E("t<aQ>"))
B.aW=new A.dF(0,"database")
B.aX=new A.dF(1,"journal")
B.T=s([B.aW,B.aX],A.E("t<dF>"))
B.ac=new A.cZ(0,"insert")
B.ad=new A.cZ(1,"update")
B.ae=new A.cZ(2,"delete")
B.b4=s([B.ac,B.ad,B.ae],A.E("t<cZ>"))
B.u=s([],t.s)
B.b5=s([],t.c)
B.aV=new A.bs("s",0,"opfsShared")
B.aT=new A.bs("i",3,"indexedDb")
B.aU=new A.bs("m",4,"inMemory")
B.b6=s([B.aV,B.Q,B.R,B.aT,B.aU],A.E("t<bs>"))
B.aY=new A.cI("/database",0,"database")
B.aZ=new A.cI("/database-journal",1,"journal")
B.U=s([B.aY,B.aZ],A.E("t<cI>"))
B.af=new A.bz(0,"opfs")
B.ag=new A.bz(1,"indexedDb")
B.be=new A.bz(2,"inMemory")
B.b7=s([B.af,B.ag,B.be],A.E("t<bz>"))
B.aQ=new A.bo(1,"getAutoCommit")
B.aR=new A.bo(2,"executeBatchInTransaction")
B.aS=new A.bo(3,"updateSubscriptionManagement")
B.b8=s([B.N,B.aQ,B.aR,B.aS,B.O],A.E("t<bo>"))
B.aq=new A.Z(A.nS(),A.aL(),0,"xAccess",t.b0)
B.ar=new A.Z(A.nS(),A.bk(),1,"xDelete",A.E("Z<az,aE>"))
B.aC=new A.Z(A.nS(),A.aL(),2,"xOpen",t.b0)
B.aA=new A.Z(A.aL(),A.aL(),3,"xRead",t.dx)
B.av=new A.Z(A.aL(),A.bk(),4,"xWrite",t.R)
B.aw=new A.Z(A.aL(),A.bk(),5,"xSleep",t.R)
B.ax=new A.Z(A.aL(),A.bk(),6,"xClose",t.R)
B.aB=new A.Z(A.aL(),A.aL(),7,"xFileSize",t.dx)
B.ay=new A.Z(A.aL(),A.bk(),8,"xSync",t.R)
B.az=new A.Z(A.aL(),A.bk(),9,"xTruncate",t.R)
B.at=new A.Z(A.aL(),A.bk(),10,"xLock",t.R)
B.au=new A.Z(A.aL(),A.bk(),11,"xUnlock",t.R)
B.as=new A.Z(A.bk(),A.bk(),12,"stopServer",A.E("Z<aE,aE>"))
B.b9=s([B.aq,B.ar,B.aC,B.aA,B.av,B.aw,B.ax,B.aB,B.ay,B.az,B.at,B.au,B.as],A.E("t<Z<bb,bb>>"))
B.A=new A.w(A.qd(),0,"dedicatedCompatibilityCheck",t.x)
B.o=new A.w(A.vH(),1,"sharedCompatibilityCheck",t.x)
B.y=new A.w(A.qd(),2,"dedicatedInSharedCompatibilityCheck",t.x)
B.a1=new A.w(A.vx(),3,"custom",A.E("w<bp>"))
B.a2=new A.w(A.vK(),4,"open",A.E("w<c5>"))
B.a3=new A.w(A.vO(),5,"runQuery",A.E("w<c9>"))
B.a9=new A.w(A.vB(),6,"fileSystemExists",A.E("w<bW>"))
B.V=new A.w(A.vA(),7,"fileSystemAccess",A.E("w<bV>"))
B.aa=new A.w(A.vC(),8,"fileSystemFlush",A.E("w<bX>"))
B.a4=new A.w(A.vw(),9,"connect",A.E("w<b6>"))
B.a6=new A.w(A.vQ(),10,"startFileSystemServer",A.E("w<b_>"))
B.B=new A.w(A.vI(),11,"updateRequest",t.b)
B.v=new A.w(A.vG(),12,"rollbackRequest",t.b)
B.z=new A.w(A.vD(),13,"commitRequest",t.b)
B.w=new A.w(A.vP(),14,"simpleSuccessResponse",A.E("w<X>"))
B.a8=new A.w(A.vN(),15,"rowsResponse",A.E("w<aZ>"))
B.a7=new A.w(A.vz(),16,"errorResponse",A.E("w<br>"))
B.Z=new A.w(A.vy(),17,"endpointResponse",A.E("w<bq>"))
B.a_=new A.w(A.vM(),18,"exclusiveLock",A.E("w<c8>"))
B.X=new A.w(A.vL(),19,"releaseLock",A.E("w<c7>"))
B.W=new A.w(A.vv(),20,"closeDatabase",A.E("w<bP>"))
B.a5=new A.w(A.vJ(),21,"openAdditionalConnection",A.E("w<c4>"))
B.Y=new A.w(A.vR(),22,"notifyUpdate",A.E("w<bB>"))
B.x=new A.w(A.vF(),23,"notifyRollback",t.dh)
B.C=new A.w(A.vE(),24,"notifyCommit",t.dh)
B.a0=new A.w(A.vu(),25,"abort",A.E("w<bn>"))
B.ba=s([B.A,B.o,B.y,B.a1,B.a2,B.a3,B.a9,B.V,B.aa,B.a4,B.a6,B.B,B.v,B.z,B.w,B.a8,B.a7,B.Z,B.a_,B.X,B.W,B.a5,B.Y,B.x,B.C,B.a0],A.E("t<w<A>>"))
B.bd={}
B.bb=new A.dA(B.bd,[],A.E("dA<o,b>"))
B.bA=new A.j9(2,"readWriteCreate")
B.D=new A.ev(!1,!1)
B.bf=A.aS("dx")
B.bg=A.aS("mV")
B.bh=A.aS("iF")
B.bi=A.aS("iG")
B.bj=A.aS("iT")
B.bk=A.aS("iU")
B.bl=A.aS("iV")
B.bm=A.aS("l")
B.bn=A.aS("jR")
B.bo=A.aS("jS")
B.bp=A.aS("jT")
B.bq=A.aS("cd")
B.br=new A.aq(10)
B.bs=new A.aq(12)
B.ao=new A.aq(14)
B.bt=new A.aq(2570)
B.bu=new A.aq(3850)
B.bv=new A.aq(522)
B.ap=new A.aq(778)
B.bw=new A.aq(8)
B.bx=new A.de("reaches root")
B.F=new A.de("below root")
B.G=new A.de("at root")
B.H=new A.de("above root")
B.i=new A.df("different")
B.I=new A.df("equal")
B.j=new A.df("inconclusive")
B.J=new A.df("within")})();(function staticFields(){$.lO=null
$.cv=A.n([],A.E("t<l>"))
$.oA=null
$.o7=null
$.o6=null
$.q7=null
$.q3=null
$.qe=null
$.mx=null
$.mE=null
$.nP=null
$.lV=A.n([],A.E("t<u<l>?>"))
$.dk=null
$.eP=null
$.eQ=null
$.nH=!1
$.q=B.e
$.p3=null
$.p4=null
$.p5=null
$.p6=null
$.no=A.ks("_lastQuoRemDigits")
$.np=A.ks("_lastQuoRemUsed")
$.ed=A.ks("_lastRemUsed")
$.nq=A.ks("_lastRem_nsh")
$.oX=""
$.oY=null
$.pJ=null
$.mn=null})();(function lazyInitializers(){var s=hunkHelpers.lazyFinal,r=hunkHelpers.lazy
s($,"w4","cD",()=>A.vh("_$dart_dartClosure"))
s($,"wU","qO",()=>B.e.f0(new A.mH()))
s($,"wO","qL",()=>A.n([new J.fn()],A.E("t<dY>")))
s($,"wk","qp",()=>A.be(A.jQ({
toString:function(){return"$receiver$"}})))
s($,"wl","qq",()=>A.be(A.jQ({$method$:null,
toString:function(){return"$receiver$"}})))
s($,"wm","qr",()=>A.be(A.jQ(null)))
s($,"wn","qs",()=>A.be(function(){var $argumentsExpr$="$arguments$"
try{null.$method$($argumentsExpr$)}catch(q){return q.message}}()))
s($,"wq","qv",()=>A.be(A.jQ(void 0)))
s($,"wr","qw",()=>A.be(function(){var $argumentsExpr$="$arguments$"
try{(void 0).$method$($argumentsExpr$)}catch(q){return q.message}}()))
s($,"wp","qu",()=>A.be(A.oV(null)))
s($,"wo","qt",()=>A.be(function(){try{null.$method$}catch(q){return q.message}}()))
s($,"wt","qy",()=>A.be(A.oV(void 0)))
s($,"ws","qx",()=>A.be(function(){try{(void 0).$method$}catch(q){return q.message}}()))
s($,"wx","nV",()=>A.to())
s($,"w9","dt",()=>$.qO())
s($,"w8","ql",()=>A.tA(!1,B.e,t.y))
s($,"wK","qI",()=>A.ox(4096))
s($,"wI","qG",()=>new A.mb().$0())
s($,"wJ","qH",()=>new A.ma().$0())
s($,"wy","qB",()=>A.rT(A.pK(A.n([-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-2,-1,-2,-2,-2,-2,-2,62,-2,62,-2,63,52,53,54,55,56,57,58,59,60,61,-2,-2,-2,-1,-2,-2,-2,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,-2,-2,-2,-2,63,-2,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,-2,-2,-2,-2,-2],t.t))))
s($,"wF","aM",()=>A.ec(0))
s($,"wD","eW",()=>A.ec(1))
s($,"wE","qE",()=>A.ec(2))
s($,"wB","nX",()=>$.eW().ah(0))
s($,"wz","nW",()=>A.ec(1e4))
r($,"wC","qD",()=>A.aO("^\\s*([+-]?)((0x[a-f0-9]+)|(\\d+)|([a-z0-9]+))\\s*$",!1))
s($,"wA","qC",()=>A.ox(8))
s($,"wG","qF",()=>typeof FinalizationRegistry=="function"?FinalizationRegistry:null)
s($,"wL","mT",()=>A.mI(B.bm))
s($,"wM","qJ",()=>Symbol("jsBoxedDartObjectProperty"))
s($,"wc","qn",()=>{var q=new A.lN(new DataView(new ArrayBuffer(A.uk(8))))
q.fB()
return q})
s($,"wV","eX",()=>A.od(null,$.eV()))
s($,"wR","nY",()=>new A.f9($.nU(),null))
s($,"wh","qo",()=>new A.jb(A.aO("/",!0),A.aO("[^/]$",!0),A.aO("^/",!0)))
s($,"wj","hK",()=>new A.kc(A.aO("[/\\\\]",!0),A.aO("[^/\\\\]$",!0),A.aO("^(\\\\\\\\[^\\\\]+\\\\[^\\\\/]+|[a-zA-Z]:[/\\\\])",!0),A.aO("^[/\\\\](?![/\\\\])",!0)))
s($,"wi","eV",()=>new A.jX(A.aO("/",!0),A.aO("(^[a-zA-Z][-+.a-zA-Z\\d]*://|[^/])$",!0),A.aO("[a-zA-Z][-+.a-zA-Z\\d]*://[^/]*",!0),A.aO("^/",!0)))
s($,"wg","nU",()=>A.tg())
s($,"wQ","qN",()=>A.o4("-9223372036854775808"))
s($,"wP","qM",()=>A.o4("9223372036854775807"))
s($,"wT","hL",()=>{var q=$.qF()
q=q==null?null:new q(A.cz(A.w0(new A.my(),A.E("b7")),1))
return new A.hj(q,A.E("hj<b7>"))})
s($,"w2","eU",()=>A.oK())
s($,"w1","mQ",()=>A.rG(A.n(["files","blocks"],t.s)))
s($,"w6","mR",()=>{var q,p,o=A.a4(t.N,t.v)
for(q=0;q<2;++q){p=B.U[q]
o.p(0,p.c,p)}return o})
s($,"w5","nT",()=>new A.fe(new WeakMap()))
s($,"wN","qK",()=>B.aP)
r($,"ww","mS",()=>{var q="navigator"
return A.rC(A.rD(A.nO(A.qg(),q),"locks"))?new A.k9(A.nO(A.nO(A.qg(),q),"locks")):null})
s($,"wa","qm",()=>A.rk(B.ba,A.E("w<A>")))
r($,"wv","qA",()=>new A.ie())
s($,"wu","qz",()=>{var q,p=J.op(256,t.N)
for(q=0;q<256;++q)p[q]=B.a.eR(B.b.j8(q,16),2,"0")
return p})
s($,"w3","qk",()=>A.oK())})();(function nativeSupport(){!function(){var s=function(a){var m={}
m[a]=1
return Object.keys(hunkHelpers.convertToFastObject(m))[0]}
v.getIsolateTag=function(a){return s("___dart_"+a+v.isolateTag)}
var r="___dart_isolate_tags_"
var q=Object[r]||(Object[r]=Object.create(null))
var p="_ZxYxX"
for(var o=0;;o++){var n=s(p+"_"+o+"_")
if(!(n in q)){q[n]=1
v.isolateTag=n
break}}v.dispatchPropertyName=v.getIsolateTag("dispatch_record")}()
hunkHelpers.setOrUpdateInterceptorsByTag({SharedArrayBuffer:A.cP,ArrayBuffer:A.c1,ArrayBufferView:A.dR,DataView:A.c2,Float32Array:A.fA,Float64Array:A.fB,Int16Array:A.fC,Int32Array:A.cQ,Int8Array:A.fD,Uint16Array:A.fE,Uint32Array:A.fF,Uint8ClampedArray:A.dS,CanvasPixelArray:A.dS,Uint8Array:A.c3})
hunkHelpers.setOrUpdateLeafTags({SharedArrayBuffer:true,ArrayBuffer:true,ArrayBufferView:false,DataView:true,Float32Array:true,Float64Array:true,Int16Array:true,Int32Array:true,Int8Array:true,Uint16Array:true,Uint32Array:true,Uint8ClampedArray:true,CanvasPixelArray:true,Uint8Array:false})
A.cR.$nativeSuperclassTag="ArrayBufferView"
A.ep.$nativeSuperclassTag="ArrayBufferView"
A.eq.$nativeSuperclassTag="ArrayBufferView"
A.bx.$nativeSuperclassTag="ArrayBufferView"
A.er.$nativeSuperclassTag="ArrayBufferView"
A.es.$nativeSuperclassTag="ArrayBufferView"
A.aA.$nativeSuperclassTag="ArrayBufferView"})()
Function.prototype.$0=function(){return this()}
Function.prototype.$1=function(a){return this(a)}
Function.prototype.$2=function(a,b){return this(a,b)}
Function.prototype.$3=function(a,b,c){return this(a,b,c)}
Function.prototype.$4=function(a,b,c,d){return this(a,b,c,d)}
Function.prototype.$1$1=function(a){return this(a)}
Function.prototype.$5=function(a,b,c,d,e){return this(a,b,c,d,e)}
convertAllToFastObject(w)
convertToFastObject($);(function(a){if(typeof document==="undefined"){a(null)
return}if(typeof document.currentScript!="undefined"){a(document.currentScript)
return}var s=document.scripts
function onLoad(b){for(var q=0;q<s.length;++q){s[q].removeEventListener("load",onLoad,false)}a(b.target)}for(var r=0;r<s.length;++r){s[r].addEventListener("load",onLoad,false)}})(function(a){v.currentScript=a
var s=A.vr
if(typeof dartMainRunner==="function"){dartMainRunner(s,[])}else{s([])}})})()
//# sourceMappingURL=powersync_db.worker.js.map
