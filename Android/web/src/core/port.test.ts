import {describe,it,expect,vi} from 'vitest';
import {readFileSync} from 'node:fs';
import {moon,separation,sun} from './astro';
import {planetPosition} from './planets';
import {makeContext,computeHorizon,inRange,blockedByWindows} from './geometry';
import {accessStatus} from './access';
import {evaluate} from './recommender';
import {WeatherClient,nearestWeather} from './weather';
import type {Spot,CityScene,Catalog,Weather} from './types';
import {imagePlacement} from './constellation-image';
const data=JSON.parse(readFileSync(new URL('../../public/generated/data.json',import.meta.url),'utf8')) as {spots:Spot[];scenes:CityScene[];catalog:Catalog};
const date=new Date('2026-10-24T12:00:00Z');
describe('iPhone版と共通の外部参照値',()=>{
  it.each([['2026-10-24T12:00:00Z',57.63,151.94,.963],['2026-10-25T15:00:00Z',62.59,219.45,.995],['2026-01-01T10:00:00Z',54.54,92.27,.940]] as const)('Astronomy Engine 月 %s',(iso,altitude,azimuth,fraction)=>{const m=moon(new Date(iso),35.658,139.7016);expect(separation(m.position,{altitude,azimuth})).toBeLessThan(.7);expect(Math.abs(m.fraction-fraction)).toBeLessThan(.02);});
  it.each([['mercury',-39.959,271.652],['venus',-55.396,292.395],['mars',-27.135,37.795],['jupiter',-33.955,31.658],['saturn',52.114,150.801]] as const)('JPL DE421 惑星 %s',(id,altitude,azimuth)=>{expect(separation(planetPosition(id,date,35.658,139.702816),{altitude,azimuth})).toBeLessThan(.3);});
  it('東京の21時は太陽が地平線下',()=>expect(Math.abs(sun(date,35.658,139.7016).altitude+49.19)).toBeLessThan(1));
});
describe('遮蔽・データ・未確認条件',()=>{
  const spot={...data.spots[0],latitude:0,longitude:0,floorElevation:0,eyeHeight:1.5,hostBuildingId:undefined};
  const scene:CityScene={id:'test',name:'test',originLatitude:0,originLongitude:0,groundElevation:0,source:'test',buildings:[{id:'tower',name:'tower',x:0,y:100,width:20,depth:20,height:100}]};
  it('北のビルは南を遮らず、高い観測地点では見下ろす',()=>{const h=computeHorizon(spot,scene);expect(h[0]).toBeCloseTo(Math.atan2(98.5,90)*180/Math.PI,6);expect(h[180]).toBe(0);expect(computeHorizon({...spot,floorElevation:150},scene).every(v=>v===0)).toBe(true);});
  it('北をまたぐ窓と天井',()=>{expect(inRange(0,300,60)).toBe(true);expect(inRange(180,300,60)).toBe(false);expect(blockedByWindows({...spot,maxVisibleAltitude:45},0,60)).toBe(true);});
  it('実データ43地点と32都市を利用する',()=>{expect(data.spots).toHaveLength(43);expect(data.scenes).toHaveLength(32);for(const s of data.spots)if(s.sceneId)expect(data.scenes.some(c=>c.id===s.sceneId)).toBe(true);});
  it('デモ：地上の月はビルに隠れ、展望台は遮蔽を超える',()=>{const scene=data.scenes.find(c=>c.id==='shibuya')!;const moonTarget=data.catalog.targets[0];const results=['shibuya_east_plaza','shibuya_sky'].map(id=>evaluate(makeContext(data.spots.find(s=>s.id===id)!,scene),moonTarget,date,data.catalog.stars));expect(results[0].altitude).toBeGreaterThan(0);expect(results[0].visible).toBe(false);expect(results[1].visible).toBe(true);expect(results[1].tier).not.toBe('recommended');});
  it('日本時間の夜間営業と最終入場',()=>{const s={...spot,accessRules:undefined,openingHours:{alwaysOpen:false,open:'18:00',close:'02:00',lastAdmission:'01:30'}};expect(accessStatus(s,new Date('2026-10-24T16:00:00Z'))).toBe('open');expect(accessStatus(s,new Date('2026-10-24T16:45:00Z'))).toBe('closed');});
});
describe('天気は未取得を晴れとみなさない',()=>{
  it('標準fetchをクライアントのメソッドとして呼ばない',async()=>{vi.stubGlobal('fetch',function(this:unknown){if(this instanceof WeatherClient)throw TypeError('Illegal invocation');return Promise.resolve(new Response(JSON.stringify({hourly:{time:[+date/1000],cloud_cover:[10],precipitation:[0]}})));});try{const client=new WeatherClient();expect(await client.refresh([data.spots[0]])).toBe(0);expect(client.at(data.spots[0],date)?.cloudCover).toBe(10);}finally{vi.unstubAllGlobals();}});
  it('90分を超える予報は使わない',()=>{const samples:Weather[]=[{time:date.getTime(),cloudCover:0,precipitation:0,wind:null,visibility:null}];expect(nearestWeather(samples,new Date(+date+91*60000))).toBeUndefined();});
  it('通信失敗を未取得として返す',async()=>{const client=new WeatherClient(async()=>{throw Error('offline');});expect(await client.refresh([data.spots[0]])).toBe(1);expect(client.at(data.spots[0],date)).toBeUndefined();});
});
describe('88星座の絵の位置',()=>{
  it('すべての基準星を絵の正しい位置へ合わせる',()=>{expect(data.catalog.images).toHaveLength(88);for(const image of data.catalog.images){const place=imagePlacement(image);for(const a of image.anchors){const p=place(a.pixel[0],a.pixel[1]);expect(separation({altitude:p.dec,azimuth:p.ra},{altitude:a.star[1],azimuth:a.star[0]})).toBeLessThan(.001);}}});
});
describe('最新developの地形と部分形状',()=>{
  it.each([[63,21.422],[105,31.691],[127,9.801],[152,64.658],[300,81.580]])('Swiftの遮蔽回帰値：方位%s°',(az,expected)=>{const s=data.spots.find(s=>s.id==='shibuya_east_plaza')!,scene=data.scenes.find(c=>c.id==='shibuya')!;expect(computeHorizon(s,scene)[az]).toBeCloseTo(expected,2);});
  it('部分の箱があれば建物全体の大きな箱で空を塞がない',()=>{const spot={...data.spots[0],latitude:0,longitude:0,floorElevation:0,eyeHeight:1.5,hostBuildingId:undefined};const scene:CityScene={id:'parts',name:'parts',originLatitude:0,originLongitude:0,groundElevation:0,source:'test',buildings:[{id:'b',name:'b',x:0,y:100,width:100,depth:20,height:100,parts:[{x:40,y:100,width:10,depth:20,height:100}]}]};expect(computeHorizon(spot,scene)[0]).toBe(0);});
  it('周囲の高い地形を地平線へ合成する',()=>{const spot={...data.spots[0],floorElevation:0,eyeHeight:1.5,approxHorizonElevation:0};const terrain={source:'test',spots:{[spot.id]:Array.from({length:360},()=>[101.5,100] as [number,number])}};expect(makeContext(spot,undefined,terrain).horizon[0]).toBeCloseTo(45);});
  it('雲量90%はデータが揃っていても推薦しない',()=>{const spot={...data.spots.find(s=>s.id==='shibuya_sky')!,openingHours:{alwaysOpen:true},accessRules:undefined,directionMaskVerified:true,viewingDirectionMask:undefined,lastVerifiedAt:'2026-10-25',regionalLightIndex:.8};const c=makeContext(spot,data.scenes.find(c=>c.id==='shibuya'));expect(evaluate(c,data.catalog.targets[0],date,data.catalog.stars,{time:+date,cloudCover:90,precipitation:0,wind:0,visibility:10000}).tier).toBe('needsCheck');});
});
