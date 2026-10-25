export {};
declare global {
  interface Window {
    Astera?:{back():boolean;suspend():void};
    AsteraDevice?:{available():boolean;setTracking(enabled:boolean):void;soundAllowed?():boolean;declination?(lat:number,lon:number,alt:number,time:number):number};
  }
}
