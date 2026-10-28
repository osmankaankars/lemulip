'use strict';
// Deterministic controller checks; real playback/layout is checked in browsers.
const assert = require('node:assert/strict');
const init = require('../site/demo-view.js');
class Element {
  constructor() { this.hidden = false; this.inert = false; this.attrs = {}; this.handlers = {}; this.textContent = ''; this.paused = true; this.playCount = 0; this.pauseCount = 0; this.focused = false; this.classes = new Set(); this.classList = { toggle: (name, state) => state ? this.classes.add(name) : this.classes.delete(name) }; }
  setAttribute(k,v) { this.attrs[k] = String(v); }
  removeAttribute(k) { delete this.attrs[k]; }
  addEventListener(name, fn) { this.handlers[name] = fn; }
  fire(name, value = {}) { this.handlers[name]?.(value); }
  focus() { this.focused = true; }
  play() { this.playCount++; this.paused = false; return Promise.resolve(); }
  pause() { this.pauseCount++; this.paused = true; }
}
const ids = ['watch-native','demo-stage','desktop-demo','native-recording','native-video','demo-controls','demo-source','origin-desktop','origin-finder','native-error'];
const elements = Object.fromEntries(ids.map(id => [id, new Element()]));
const listeners = {}, events = [];
const document = { hidden:false, fullscreenElement:null, getElementById:id=>elements[id], addEventListener:(name,fn)=>listeners[name]=fn, dispatchEvent:event=>events.push(event.type) };
init(document);
const e=elements;
assert.equal(e['native-video'].playCount,0,'No playback on initialization');
assert.equal(e['watch-native'].hidden,false);
e['watch-native'].fire('click');
assert.equal(e['native-recording'].hidden,false);
assert.equal(e['native-video'].playCount,1,'Only the explicit watch action plays');
assert.equal(e['desktop-demo'].inert,true);
assert.equal(e['demo-controls'].inert,true);
assert.equal(e['watch-native'].attrs['aria-pressed'],'true');
assert.ok(events.includes('lemulip:watch-native'),'Stop the illustrated tour before showing recording');
assert.ok(e['native-video'].focused,'Keyboard focus enters the visible player');
document.hidden=true;listeners.visibilitychange();
assert.equal(e['native-video'].paused,true);
document.hidden=false;listeners.visibilitychange();
assert.equal(e['native-video'].playCount,1,'Returning to the page does not restart a movie');
e['origin-finder'].fire('click');
assert.equal(e['native-recording'].hidden,true);
assert.equal(e['desktop-demo'].inert,false);
assert.equal(e['demo-controls'].inert,false);
assert.equal(e['watch-native'].attrs['aria-pressed'],'false');
e['watch-native'].fire('click');
let prevented=false;
e['demo-stage'].fire('keydown',{key:'Escape',preventDefault(){prevented=true;}});
assert.ok(prevented);
assert.equal(e['native-recording'].hidden,true);
assert.ok(e['watch-native'].focused);
e['watch-native'].fire('click');e['native-video'].fire('error');
assert.equal(e['native-error'].hidden,false,'A real failed recording has a real fallback, not simulated footage');
assert.doesNotThrow(()=>init({getElementById:()=>null}),'Progressive enhancement tolerates an absent player');
console.log('Native recording view: 20 assertions passed');
