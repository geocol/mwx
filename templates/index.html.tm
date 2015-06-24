<title>MWX</title>
<style>
  iframe[name=pageView] {
    width: 100%;
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
  }
  window.pageView.location = url;
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
  <button type=submit onclick="elements.format.value = 'text'">Text</button>
  <button type=submit onclick="elements.format.value = 'xml'">XML</button>
</form>

<iframe name=pageView></iframe>
