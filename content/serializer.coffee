abbrevs = require('./journal-abbrev.coffee')
debug = require('./debug.coffee')

debug('Serializer loading...')

CACHE = require('./db/cache.coffee')
Formatter = require('./keymanager/formatter.coffee')
debug('Serializer loading...', Object.keys(Formatter))
KeyManager = require('./keymanager.coffee')

class Serializer
  collection: 'itemToExportFormat'

#  # prune cache on old accessed
#  prune: Zotero.Promise.coroutine(->
#    ids = yield Zotero.DB.columnQueryAsync('select itemID from items where itemID not in (select itemID from deletedItems)')
#    for id in ids
#      delete cache[id] if entry.accessed

  init: Zotero.Promise.coroutine(->
    abbrevs.init()

    debug('Serializer.init')
    fieldsWithAliases = yield Zotero.DB.queryAsync("""
      SELECT it.typeName, f.fieldName, a.fieldName as fieldAlias
      FROM baseFieldMappingsCombined bfmc
      JOIN fields f ON f.fieldID = bfmc.baseFieldID
      JOIN fields a ON a.fieldID = bfmc.fieldID
      JOIN itemTypes it ON it.itemTypeID = bfmc.itemTypeID
    """)

    ### SIMPLIFY ###
    mapping = fieldsWithAliases.reduce((map, alias) ->
      map[alias.typeName] ||= {}
      map[alias.typeName][alias.fieldAlias] = alias.fieldName
      return map
    , {})

    simplify = ''
    for itemType, aliases of mapping
      simplify += "if (item.itemType == '#{itemType}') {\n"
      for alias, field of aliases
        simplify += "item.#{field} = item.#{field} || item.#{alias};\n"
      simplify += "}\n"

    simplify += 'item.tags = item.tags ? item.tags.map(function(tag) { return tag.tag }) : [];\n'
    simplify += 'return item;'

    debug('Serializer.init: simplify =\n', simplify)
    @simplify = new Function('item', simplify)

    ### SCRUB ###
    fields = yield Zotero.DB.queryAsync("""
      SELECT it.typeName, f.fieldName
      FROM itemTypes it
      JOIN itemTypeFields itf ON it.itemTypeID = itf.itemTypeID
      JOIN fields f ON f.fieldID = itf.fieldID
    """)

    renames = ''
    seen = {}
    for field in fieldsWithAliases
      continue if seen[field.fieldAlias]
      seen[field.fieldAlias] = true
      renames += "if (item.#{field.fieldAlias}) { item.#{field.fieldName} = item.#{field.fieldAlias}; delete item.#{field.fieldAlias}; }\n"
      fields.push(field.fieldName)

    fields.push.apply(fields, [
      'key',
      'itemType',
      'creators',
      'itemID',
      'seeAlso',
      # 'relations',
      'attachments',
      # 'collections',
      'tags',
      'notes',
      'related',
    ])

    supported = ''
    seen = {}
    for field in fields
      field = { fieldName: field } if typeof field == 'string'
      continue if seen[field.fieldName]
      seen[field.fieldName] = true
      supported += "case '#{field.fieldName}':\n"

    scrub = """
      if (Array.isArray(item.tags) && item.tags.length && item.tags[0].note) {
        item.tags = item.tags.map(function(tag) { return tag.tag }).filter(function(tag) { return tag });
      }

      if (Array.isArray(item.notes) && item.notes.length && item.notes[0].note) {
        item.notes = item.notes.map(function(note) { return note.note }).filter(function(note) { return note });
      }

      if (Array.isArray(item.attachments) && item.attachments.length) {
        item.attachments.forEach(function(attachment) {
          attachment.path || (attachment.path = attachment.localPath);
        })
      }

      if (item.relations) {
        if (item.relations['dc:relation']) {
          var relations = item.relations['dc:relation'];
          if (!Array.isArray(relations)) relations = [relations];

          item.relations = relations.map(function(rel) { return rel.replace(/.*\\//, ''); });
        } else if (!Array.isArray(item.relations)) {
          delete item.relations;
        }
      }

      #{renames}

      for (var key in item) {
        switch (key) {
          #{supported}
            if (item[key] == null || item[key] == '') delete item[key];
            else if (Array.isArray(item[key]) && !item[key].length) delete item[key];
            break;
          default:
            Zotero.debug('{better-bibtex:<Translator>}: removing unsupported field ' + key + ': ' + item[key]);
            delete item[key]
        }
      }
      return item;
    """
    debug('Serializer.init: scrub =', scrub)
    @scrub = new Function('item', scrub)

    debug('Serializer.init: done')
    return
  )

  fetch: (item, legacy, skipChildItems) ->
    return null unless @cache

    cached = @cache.findOne({ itemID: item.id, legacy: !!legacy, skipChildItems: !!skipChildItems})
    return null unless cached

    serialized = cached.item
    serialized.journalAbbreviation = abbrevs.get(serialized)
    serialized.citekey = KeyManager.get(item.id).citekey if serialized.itemType not in ['note', 'attachment']
    return serialized

  store: (item, serialized, legacy, skipChildItems) ->

    # come on -- these are used in the collections export but not provided on the items?!
    serialized.itemID = item.id
    serialized.key = item.key

    if @cache ||= CACHE.getCollection(@collection)
      @cache.insert({itemID: item.id, legacy, skipChildItems, item: serialized})
    else
      Zotero.logError(new Error('Serializer.store ignored, DB not yet loaded'))

    serialized.journalAbbreviation = abbrevs.get(serialized)
    serialized.citekey = KeyManager.get(item.id).citekey if serialized.itemType not in ['note', 'attachment']
    return serialized

  serialize: (item) -> Zotero.Utilities.Internal.itemToExportFormat(item, false, true)

debug('Serializer loaded')

module.exports = new Serializer()
