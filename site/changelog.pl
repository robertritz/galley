#!/usr/bin/perl
# Renders the released sections of CHANGELOG.md as HTML for the website, and
# fills {{CHANGELOG}} and {{VERSION}} (the newest release) in the page on stdin.
#
#   perl changelog.pl ../CHANGELOG.md < index.html
use strict;
use utf8;
use warnings;

my $changelog = shift or die "usage: changelog.pl CHANGELOG.md < page.html\n";
open my $fh, '<:encoding(UTF-8)', $changelog or die "$changelog: $!\n";

sub inline {
    my $s = shift;
    $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g;
    $s =~ s/`([^`]+)`/<code>$1<\/code>/g;
    $s =~ s/\*\*([^*]+)\*\*/<b>$1<\/b>/g;
    $s =~ s/\[([^\]]+)\]\(([^)]+)\)/<a href="$2">$1<\/a>/g;
    $s =~ s/"([^"]+)"/\x{201C}$1\x{201D}/g;
    $s =~ s/'/\x{2019}/g;
    return $s;
}

# Each release: version, date, and its lines (paragraphs and "- " items).
my (@releases, $current);
while (my $line = <$fh>) {
    chomp $line;
    if ($line =~ /^## (.+?)(?: · (.+))?$/) {
        $current = $1 eq 'Unreleased' ? undef : { version => $1, date => $2 // '', lines => [] };
        push @releases, $current if $current;
    } elsif ($current && $line =~ /\S/) {
        push @{ $current->{lines} }, $line;
    }
}
die "No releases in $changelog\n" unless @releases;

my $html = qq{<ol class="releases">\n};
for my $r (@releases) {
    $html .= qq{  <li class="release" id="v$r->{version}">\n};
    $html .= qq{    <div class="release-head"><h3>$r->{version}</h3><time>$r->{date}</time></div>\n};
    $html .= qq{    <div class="release-notes">\n};
    my $in_list = 0;
    for my $l (@{ $r->{lines} }) {
        if ($l =~ /^- (.*)/) {
            $html .= qq{      <ul>\n} unless $in_list++;
            $html .= qq{        <li>} . inline($1) . qq{</li>\n};
        } else {
            $html .= qq{      </ul>\n} if $in_list; $in_list = 0;
            $html .= qq{      <p>} . inline($l) . qq{</p>\n};
        }
    }
    $html .= qq{      </ul>\n} if $in_list;
    $html .= qq{    </div>\n  </li>\n};
}
$html .= qq{</ol>};

binmode STDIN, ':encoding(UTF-8)';
binmode STDOUT, ':encoding(UTF-8)';
local $/;
my $page = <STDIN>;
$page =~ s/\{\{CHANGELOG\}\}/$html/g;
$page =~ s/\{\{VERSION\}\}/$releases[0]{version}/g;
print $page;
