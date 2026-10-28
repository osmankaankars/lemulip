/* Local catalog matching only. Never reads, remembers or uploads user files. */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.LemulipCatalogSearch = api;
})(typeof window === 'undefined' ? globalThis : window, () => {
  'use strict';
  const aliases = {
    images: 'image photo picture photograph', pdf: 'pdf document pages ocr',
    audio: 'audio sound music', video: 'video movie film',
    documents: 'document word text markdown', spreadsheets: 'spreadsheet workbook excel table',
    presentations: 'presentation slide powerpoint keynote', subtitles: 'subtitle caption',
    archives: 'archive zip tar gzip extract'
  };
  const normalize = value => String(value ?? '').normalize('NFKD').replace(/\p{Diacritic}/gu, '').toLowerCase().trim();
  const operationText = op => [op.id, op.title, op.detail].join(' ');
  function filter(catalog, query) {
    const terms = normalize(query).slice(0, 512).split(/\s+/).filter(Boolean);
    const matches = value => terms.every(term => normalize(value).includes(term));
    return {
      families: catalog.samples.filter(sample => matches([
        sample.label, aliases[sample.id] || '', sample.formats.join(' '),
        sample.tools.map(operationText).join(' '), catalog.actions.map(operationText).join(' ')
      ].join(' '))),
      tools: catalog.tools.filter(op => matches(operationText(op))),
      actions: catalog.actions.filter(op => matches(operationText(op)))
    };
  }
  return { normalize, filter };
});
