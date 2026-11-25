// Android VectorDrawable local matrix: T(translation+pivot) R(rotation) S(scale) T(-pivot).
const multiply=(l,r)=>[
 l[0]*r[0]+l[2]*r[1],l[1]*r[0]+l[3]*r[1],
 l[0]*r[2]+l[2]*r[3],l[1]*r[2]+l[3]*r[3],
 l[0]*r[4]+l[2]*r[5]+l[4],l[1]*r[4]+l[3]*r[5]+l[5]
];
const identity=[1,0,0,1,0,0];
function group(attributes){
 const allowed=new Set(["name","pivotX","pivotY","scaleX","scaleY","rotation","translateX","translateY"].map(k=>"android:"+k));
 for(const key of Object.keys(attributes))if(!allowed.has(key))throw Error("Unsupported vector group attribute "+key);
 const n=(key,initial)=>{const value=Number(attributes["android:"+key]??initial);if(!Number.isFinite(value)||Math.abs(value)>10000)throw Error("Invalid vector group "+key);return value;};
 const px=n("pivotX",0),py=n("pivotY",0),sx=n("scaleX",1),sy=n("scaleY",1),angle=n("rotation",0)*Math.PI/180;
 if(!sx||!sy)throw Error("Degenerate vector group scale");
 const c=Math.cos(angle),s=Math.sin(angle),a=c*sx,b=s*sx,cc=-s*sy,d=c*sy;
 return [a,b,cc,d,n("translateX",0)+px-a*px-cc*py,n("translateY",0)+py-b*px-d*py];
}
const pdf=(m,height)=>[m[0],-m[1],-m[2],m[3],m[4]+m[2]*height,height*(1-m[3])-m[5]];
module.exports={multiply,identity,group,pdf};
