<title>XML Viewer</title>

<ul class=xoxo></ul>

<script>
  var url = decodeURIComponent (location.search.replace (/^\?/, ''));
  var xhr = new XMLHttpRequest;
  xhr.open ('GET', url, true);
  xhr.onreadystatechange = function () {
    if (xhr.readyState === 4 && xhr.status === 200) {
      showXML (xhr.responseXML);
    }
  };
  xhr.send (null);

  function showXML (doc) {
    var parent = document.querySelector ('.xoxo');
    var items = [[doc, parent]];
    while (items.length) {
      var item = items.shift ();
      Array.prototype.forEach.call (item[0].childNodes, function (node) {
        if (node.nodeType === node.ELEMENT_NODE) {
          var li = document.createElement ('li');
          li.appendChild (document.createElement ('code'))
            .textContent = node.localName;

          if (node.attributes.length) {
            var ul = document.createElement ('ul');
            ul.className = 'attrs';
            Array.prototype.forEach.call (node.attributes, function (_) {
              var li = document.createElement ('li');
              li.innerHTML = '<code class=name></code> = <span class=value></span>';
              li.firstChild.textContent = _.name;
              li.lastChild.textContent = _.value;
              ul.appendChild (li);
            });
            li.appendChild (ul);
          }

          var ul = document.createElement ('ul');
          ul.className = 'children';
          items.unshift ([node, ul]);
          li.appendChild (ul);

          item[1].appendChild (li);
        } else if (node.nodeType === node.TEXT_NODE) {
          var li = document.createElement ('li');
          li.appendChild (document.createTextNode (node.nodeValue));
          item[1].appendChild (li);
        }
      });
    }
  } // showXML
</script>
