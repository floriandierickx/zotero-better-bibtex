nearley = require('nearley')
grammar = require('./grammar.ne')
fs = require('fs')

parser = new nearley.Parser(nearley.Grammar.fromCompiled(grammar))

parser.feed(fs.readFileSync('test/fixtures/import/Maintain the JabRef group and subgroup structure when importing a BibTeX db #97.bib', 'utf8'))

console.log(parser.results) # [[[[ "foo" ],"\n" ]]]
