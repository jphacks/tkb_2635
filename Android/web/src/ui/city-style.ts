import * as T from 'three';
export function windowsOn(group:number,date:Date) {
  const local=new Date(+date+9*3600000),minutes=(local.getUTCHours()*60+local.getUTCMinutes()-720+1440)%1440;
  return minutes>=300&&minutes<([600,690,1020][group]??0);
}
export function styleCity(root:T.Object3D,date:Date,host?:string) {
  const tag=host?'_h'+host.replace(/^bldg_/,'').replace(/[^a-z0-9]/gi,'').slice(0,8).toLowerCase():'';
  root.traverse(o=>{if(!(o instanceof T.Mesh))return;
    const name=o.name.split('/').at(-1)!.replace(/_h[a-z0-9]{8}$/,'');
    const window=/^windows_(\d)_(\d)/.exec(name);
    if(window)o.visible=windowsOn(Number(window[1]),date);
    const color=window?[0xffbd66,0xffe0a8,0xdbe8fa][Math.min(2,Number(window[2]))]:({lamps:0xffd18f,far_lights:0xf2b36b,aviation:0xff2014} as Record<string,number>)[name];
    const materials=Array.isArray(o.material)?o.material:[o.material];
    const made=materials.map(m=>{const old=m as T.MeshStandardMaterial;let next:T.Material;
      if(color!==undefined)next=new T.MeshBasicMaterial({color,side:T.DoubleSide});
      else if(name==='ground_night')next=new T.MeshBasicMaterial({map:old.map,side:T.DoubleSide});
      else {const standard=old.clone();standard.flatShading=true;standard.roughness=.85;standard.metalness=0;standard.color.setRGB(.16,.18,.27);if(standard.map){standard.emissiveMap=standard.map;standard.emissive.set(0xffffff);standard.emissiveIntensity=.18;}next=standard;}
      if(tag&&o.name.endsWith(tag)){next.transparent=true;next.opacity=.3;next.depthWrite=false;}m.dispose();return next;
    });o.material=Array.isArray(o.material)?made:made[0];
  });
}
