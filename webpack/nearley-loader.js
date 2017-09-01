'use strict';

var nearley = require('nearley-there');

function loader(source) {
  return nearley.compile(source) + '; module.exports = grammar;';
}

module.exports = loader
