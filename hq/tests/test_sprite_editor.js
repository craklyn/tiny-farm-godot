#!/usr/bin/env node
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const source = fs.readFileSync(path.join(__dirname, "../static/sprite.js"), "utf8");
class ImageData {
  constructor(width, height) {
    this.width = width; this.height = height;
    this.data = new Uint8ClampedArray(width * height * 4);
  }
}
const context = { console, ImageData, Uint8ClampedArray };
vm.createContext(context);
vm.runInContext(source, context);

const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, "../data/entities.json"), "utf8"));
const entities = Object.fromEntries(catalog.groups.flatMap(group => group.entities).map(entity => [entity.id, entity]));
for (const id of ["terrain_field", "terrain_yard", "terrain_floor"]) {
  assert.deepEqual(entities[id].frames, [[16, 16, 16, 16]]);
  assert.equal(entities[id].ground_tile, true);
}

const ground = entities.terrain_field;
assert.equal(context.spEditorRects(ground, 48, 48).length, 9);
assert.deepEqual(Array.from(context.spEditorRects(ground, 48, 48)[4]), [16, 16, 16, 16]);
assert.deepEqual(
  Array.from(context.spSaveRects(ground, { rect: [16, 16, 16, 16] }, 48, 48), x => Array.from(x)),
  [[16, 16, 16, 16]]
);
assert.equal(context.spGroundIndex(0, 0), 0);
assert.equal(context.spGroundIndex(3, 0), 0);
assert.equal(context.spGroundIndex(4, 4), 4);
assert.equal(context.spGroundIndex(5, 5), 8);

const pixels = new ImageData(16, 16);
for (let i = 0; i < pixels.data.length; i++) pixels.data[i] = i % 251;
const once = context.spRollHalf(pixels);
assert.notDeepEqual(once.data, pixels.data);
assert.deepEqual(context.spRollHalf(once).data, pixels.data);

const atlas = { frames: [[0, 0, 16, 16]] };
assert.equal(context.spEditorRects(atlas, 48, 32).length, 6);
assert.deepEqual(Array.from(context.spSaveRects(atlas, { rect: [16, 0, 16, 16] }, 48, 32)[0]), [16, 0, 16, 16]);

console.log("ok   ground cells repeat in farm order, save separately, and offset reversibly");
