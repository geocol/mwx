<title>MWX</title>
<style>
  iframe[name=pageView] {
    width: 45%;
    height: 20em;
  }
  iframe[name=dataView] {
    width: 45%;
    height: 20em;
  }
</style>

<form action=javascript: onsubmit="
  var form = this;
  var url = '/' + encodeURIComponent (form.elements.wiki.value) +
            '/' + encodeURIComponent (form.elements.lang.value) +
            '/' + encodeURIComponent (form.pageName.value) +
            '/' + encodeURIComponent (form.format.value);
  if (form.format.value === 'xml') {
    url = '/xml?' + encodeURIComponent (url);
  } else if (form.format.value === 'extracted.json') {
    url += '?rules_name=' + encodeURIComponent (form.rules_name.value);
    url = '/json?' + encodeURIComponent (url)
  }
  window[form.format.value === 'extracted.json' ? 'dataView' : 'pageView'].location = url;
">
  <select name=wiki>
    <option value=p>Wikipedia
    <option value=d>Wiktionary
  </select>
  <select name=lang>
    <option value=ja selected>日本語
    <option value=en>English
  </select>
  <input name=pageName>

  <input type=hidden name=format value=text>
  <button type=submit onclick="elements.format.value = 'open'">Original</button>
  <button type=submit onclick="elements.format.value = 'text'">Text</button>
  <button type=submit onclick="elements.format.value = 'xml'">XML</button>
  <button type=submit onclick="elements.format.value = 'categorymembers.txt'">Members</button>
  <input name=rules_name title="Name of rule set">
  <button type=submit onclick="elements.format.value = 'extracted.json'">Data</button>
</form>

<iframe name=pageView></iframe>
<iframe name=dataView></iframe>
