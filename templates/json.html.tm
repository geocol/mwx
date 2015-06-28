<title>JSON Viewer</title>

<ul class=xoxo></ul>

<script>
  var url = decodeURIComponent (location.search.replace (/^\?/, ''));
  var xhr = new XMLHttpRequest;
  xhr.open ('GET', url, true);
  xhr.onreadystatechange = function () {
    if (xhr.readyState === 4 && xhr.status === 200) {
      showJSON (JSON.parse (xhr.responseText));
    }
  };
  xhr.send (null);

  function showJSON (obj) {
    var parent = document.querySelector ('.xoxo');
    var items = [[obj, parent]];
    while (items.length) {
      var item = items.shift ();
      var li = document.createElement ('li');
      if (typeof item[0] === 'string') {
        li.innerHTML = '"<code class=string></code>"';
        li.firstElementChild.textContent = item[0];
        item[1].appendChild (li);
      } else if (typeof item[0] === 'number') {
        li.innerHTML = '<code class=number></code>';
        li.firstElementChild.textContent = item[0];
        item[1].appendChild (li);
      } else if (typeof item[0] === 'boolean') {
        li.innerHTML = '<code class=boolean></code>';
        li.firstElementChild.textContent = item[0];
        item[1].appendChild (li);
      } else if (typeof item[0] === 'null') {
        li.innerHTML = '<code class=null>null</code>';
        item[1].appendChild (li);
      } else if (item[0] instanceof Array) {
        li.appendChild (document.createTextNode ('[]'));
        var ol = document.createElement ('ol');
        ol.className = 'array';
        item[0].reverse ().forEach (function (_) {
          items.unshift ([_, ol]);
        });
        li.appendChild (ol);
      } else {
        li.appendChild (document.createTextNode ('{}'));
        var ul = document.createElement ('ul');
        ul.className = 'object';
        for (var n in item[0]) {
          items.unshift ([item[0][n], ul, n]);
        }
        li.appendChild (ul);
      }
      if (item.length >= 3) {
        li.insertBefore (document.createTextNode (': '), li.firstChild);
        li.insertBefore (document.createElement ('code'), li.firstChild).textContent = item[2];
      }
      item[1].appendChild (li);
    }
  } // showJSON
</script>
