echo "1..3"
basedir=$(cd `dirname $0`/.. && pwd)

($basedir/perl -c $basedir/bin/extract-from-pages.pl && echo "ok 1") || echo "not ok 1"
($basedir/perl -c $basedir/bin/extract-from-pages-remote.pl && echo "ok 2") || echo "not ok 2"
($basedir/perl -c $basedir/bin/get-pages-in-category.pl && echo "ok 3") || echo "not ok 3"
