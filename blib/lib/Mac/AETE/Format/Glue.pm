package Mac::AETE::Format::Glue;
use Data::Dumper;
use Fcntl;
use File::Basename;
use Mac::AETE::Parser;
use MLDBM qw(DB_File Storable);

use strict;
use vars qw(@ISA $VERSION);

@ISA = qw(Parser);
$VERSION = '0.09';

sub fixname {
    (my $ev = shift) =~ s/[^a-zA-Z0-9_]/_/g;
    $ev =~ s/^_+//;
    $ev =~ s/_+$//;
    return($ev);
}

sub fixdump {
    my($data, $var, $text) = @_[0..1];
    return unless scalar keys %$data;
    $data = Dumper $data;
    my @data = split(/\n/, $data);
    while (@data) {
        my $t = shift @data;
        if ($t =~ /\[$/) {
            $text .= $t;
            while (@data) {
                my $d = shift @data;
                $d =~ s/^\s+//;
                $text .= ' ' . $d;
                if ($d =~ /],?$/) {
                    $text .= "\n";
                    last;
                }
            }
        } else {
            $text .= $t . "\n";
        }
    }
    $text =~ s/^\$VAR1 = {/\%$var = ( \%Mac::Glue::Dialect::English::$var, \%Mac::Glue::Scripting_Additions::$var,/;
    $text =~ s/};/);/;
    return($text);
}

sub doc_events {
    my($self, $text, %e, %d) = $_[0];
    $text = "=head2 Events\n\n=over 4\n\n";
    %e = %{$self->{E }};
    %d = %{$self->{DE}};
    foreach my $e (sort keys %e) {
        my($d, $p, %p);
        $d = $e{$e}{params}{'----'}[1] if $e{$e}{params}{'----'}[1] ne 'null';
        %p = map {($_, $e{$e}{params}{$_})} keys %{$e{$e}{params}};
        delete($p{'----'});
        $p = join (', ', map {"$_ => $p{$_}[1]"} sort keys %p);
        $text .= sprintf("=item \$obj->%s(%s%s%s)\n\n%s\n\n%s",
            $e, ($d ? $d : ''), ($p && $d ? ', ' : ''),
            ($p ? "{$p}" : ''), $d{$e}{desc},
            ($e{$e}{reply}[1] ? "Reply type: $e{$e}{reply}[0]\n\n" : ''));

        if ($d || $p) {
            $text .= "Parameters:\n\n";
            $text .= join '',
                map {   my $x = $_ eq '----' ? 'direct object' : $_;
                        "    $x: $d{$e}{params}{$_}\n"}
                ('----', sort keys %p);
            $text .= "\n";
        }
    }
    $text .= "=back\n\n";
    return($text);
}

sub doc_classes {
    my($self, $text, %c, %d) = $_[0];
    $text = "=head2 Classes\n\n=over 4\n\n";
    return unless $self->{C}; 
    %c = %{$self->{C }};
    %d = $self->{DC} ? %{$self->{DC}} : ();
    foreach my $c (sort keys %c) {
        my(%p);
        %p = map {($_, $c{$c}{properties}{$_})} keys %{$c{$c}{properties}};
# ???   %e = map {($_, $c{$c}{elements}{$_})}   keys %{$c{$c}{elements}};
        $text .= sprintf("=item $c%s\n\n", ($d{$c}{desc} ? ": $d{$c}{desc}" : ''));

        if (each %p) {
            $text .= "Properties:\n\n";
            $text .= join '',
                map {"    $_ ($c{$c}{properties}{$_}[1]): $d{$c}{properties}{$_}\n"}
                (sort keys %p);
            $text .= "\n";
        }
    }
    $text .= "=back\n\n";
    return($text);
}

sub finish {
    my($self) = @_;

    tie my %dbm, 'MLDBM', $self->{OUTPUT}, O_CREAT|O_RDWR|O_EXCL,
        0640 or die $!;

    $dbm{CLASS} = $self->{C};
    $dbm{EVENT} = $self->{E};
    $dbm{APP}   = $self->{ID};

    foreach (@{$self}{qw(START MIDDLE FINISH)}) {
        s/__APPNAME__/$self->{TITLE}/g;
        s/__APPID__/$self->{ID}/g;
    }

    local *FILE;
    sysopen FILE, "$$self{OUTPUT}.pod", O_CREAT|O_WRONLY|O_EXCL or die $!;
    MacPerl::SetFileInfo(qw(McPL McPp), $self->{OUTPUT});
    MacPerl::SetFileInfo(qw(·uck TEXT), "$$self{OUTPUT}.pod");

#     print $self->{START};
#     print fixdump($self->{E}, 'EVENT');
#     print fixdump($self->{C}, 'CLASS');

    print FILE $self->{MIDDLE};
    print FILE doc_events($self);
    print FILE doc_classes($self);
    print FILE $self->{FINISH};
}

sub new {
    my $type = shift or die;
    my $output = shift or die;
    my $self = {OUTPUT => $output, _init()};
    return(bless($self, $type));
}

sub write_title {
    my($self, $title) = @_;
    $self->{ID} = (MacPerl::GetFileInfo($title))[0];
    $self->{TITLE} = basename($self->{OUTPUT});
}

sub write_version {
    my($self, $version) = @_;
    $self->{VERSION} = $version;
}

sub start_suite {
    my($self, $name, $desc, $id) = @_;
}

sub end_suite {
    my($self) = @_;
}

sub start_event {
    my($self, $name, $desc, $class, $id, $ev, $en, $c) = @_;
    $ev = fixname($name);
    $en = $ev;
    $c = 2;
    while (exists($self->{E}{$en})) {
        $en = $ev . $c++;
    }
    @{$self->{E }{$en}}{qw(class event)} = ($class, $id);
      $self->{DE}{$en}{desc}             = $desc;
    $self->{CE} = $en;
}

sub end_event {
    my($self) = @_;
    undef($self->{CE});
}

sub write_reply {
    my($self, $type, $desc, $req, $list, $enum) = @_;
    $self->{E }{$self->{CE}}{reply} = [$type, $req, $list, $enum];
    $self->{DE}{$self->{CE}}{reply} = $desc;
}

sub write_dobj {
    my($self, $type, $desc, $req, $list, $enum, $change) = @_;
    $self->{E }{$self->{CE}}{params}{'----'} = ['----', $type, $req, $list, $enum, $change];
    $self->{DE}{$self->{CE}}{params}{'----'} = $desc;
}

sub write_param {
    my($self, $name, $id, $type, $desc, $req, $list, $enum) = @_;
    my $ev = fixname($name);
    $self->{E }{$self->{CE}}{params}{$ev} = [$id, $type, $req, $list, $enum];
    $self->{DE}{$self->{CE}}{params}{$ev} = $desc;
}

sub begin_class {
    my($self, $name, $id, $desc, $ev, $en, $c) = @_;
    $ev = fixname($name);
    $en = $ev;
    $c = 2;
    while (exists($self->{E}{$en})) {
        $en = $ev . $c++;
    }
    $self->{C }{$en}{id} = $id;
    $self->{DC}{$en}{desc} = $desc;
    $self->{CC} = $en;
}

sub end_class {
    my($self) = @_;
    undef($self->{CE});
}

sub write_property {
    my($self, $name, $id, $class, $desc, $list, $enum, $rdonly) = @_;
    my $ev = fixname($name);
    $self->{C }{$self->{CC}}{properties}{$ev} = [$id, $class, $list, $enum, $rdonly];
    $self->{DC}{$self->{CC}}{properties}{$ev} = $desc;
}

sub end_properties {
    my($self) = @_;
}

sub write_element {
    my($self, $name, @keys) = @_;
    my $ev = fixname($name);
    $self->{C }{$self->{CC}}{elements}{$ev} = [@keys];
}

sub write_comparison {
#    print "# OK\n";
}

sub begin_enumeration {
#    my ($self, $id) = @_;
#    print "\n\@ENUMERATION \'$id\'\n";
}

sub end_enumeration {
#    print "\n";
}

sub write_enum {
#    my ($self, $name, $id, $comment) = @_;
#    print "\@ENUM \"$name\", \'$id\', \"$comment\"\n";
}

sub _init {
    my(%self);
    $self{START} =<<'EOT';
package Mac::Glue::__APPNAME__;
use strict;
use vars qw($VERSION $APP %EVENT %CLASS @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Mac::Glue;
use Mac::Glue::Dialect::English;
use Mac::Glue::Scripting_Additions;
@ISA = qw(Mac::Glue);
@EXPORT = qw(obj_form);
@EXPORT_OK = @Mac::Glue::EXPORT;
%EXPORT_TAGS = (all=>[@EXPORT, @EXPORT_OK]);
$VERSION = '0.01';
sub new {
    my($class) = 
        Mac::Glue::merge({%CLASS},
        \%Mac::Glue::Dialect::English::CLASS,
        \%Mac::Glue::Scripting_Additions::CLASS)
        ;#: \%CLASS;
    bless {
        'APP' => $APP, 'EVENT' => \%EVENT, 'CLASS' => $class, 'SWITCH' => 0
    }, shift
}
$APP = '__APPID__';

EOT

    $self{MIDDLE} = <<'EOT';

1;
__END__

=head1 NAME

Mac::Glue::__APPNAME__ - Control __APPNAME__ app

=head1 SYNOPSIS

    use Mac::Glue::__APPNAME__;
    my $obj = new Mac::Glue::__APPNAME__;

=head1 DESCRIPTION

See C<Mac::Glue> for complete documentation on base usage and framework.

EOT

    $self{FINISH} = <<EOT;
=head1 AUTHOR

Module developed by ${\($ENV{'USER'} || '????')}.

Created using F<glue_me.dp> by Chris Nandor.

Chris Nandor F<E<lt>pudge\@pobox.comE<gt>>
http://pudge.net/

Copyright (c) 1998 Chris Nandor.  All rights reserved.  This program is free 
software; you can redistribute it and/or modify it under the same terms as 
Perl itself.  Please see the Perl Artistic License.

=head1 SEE ALSO

Mac::AppleEvents, Mac::AppleEvents::Simple, macperlcat, Inside Macintosh: 
Interapplication Communication.

=cut
EOT

    return(%self);
}
1;

__END__
