package Wasm::AssemblyScript::Object;

=encoding utf-8

=head1 NAME

Wasm::AssemblyScript::Object

=head1 DESCRIPTION

This class interacts with an allocated block of memory in the
WebAssembly object.

=cut

#----------------------------------------------------------------------

use Carp ();

use constant {
    _IDX_ASCRIPT => 0,
    _IDX_MEMBASE => 1,
    _IDX_PTR => 2,
    _IDX_PINNED => 3,
};

#----------------------------------------------------------------------

=head1 METHODS

See L<https://www.assemblyscript.org/garbage-collection.html#runtime-interface>
for more information on this interface.

=head2 $num = I<OBJ>->ptr()

Returns a numeric pointer to I<OBJ>’s block of WebAssembly
memory. This number is suitable to give as a WebAssembly function parameter.

=cut

sub ptr { $_[0][ _IDX_PTR ] }

=head2 $num = I<OBJ>->pin()

“Pins” I<OBJ>’s block of WebAssembly memory.
(See AssemblyScript’s runtime documentation for more details.)

Returns I<OBJ>.

=cut

sub pin {
    my ($self) = @_;

    if ($self->[_IDX_PINNED]) {
        Carp::confess 'Already pinned!';
    }

    $self->[ _IDX_ASCRIPT ]->{'__pin'}->( $self->[_IDX_PTR] );

    return $self;
}

=head2 $yn = I<OBJ>->pinned()

Returns a boolean that indicates whether I<OBJ> is pinned.

=cut

sub pinned { $_[0][ _IDX_PINNED ] || 0 }

=head2 $obj = I<OBJ>->pin()

“Unpins” I<OBJ>’s block of WebAssembly memory.
(See AssemblyScript’s runtime documentation for more details.)

Automatically called (if needed) when I<OBJ> is garbage-collected.

Returns I<OBJ>.

=cut

sub unpin {
    my ($self) = @_;

    if (!$self->[_IDX_PINNED]) {
        Carp::confess 'Not pinned!';
    }

    $self->[ _IDX_ASCRIPT ]->{'__unpin'}->( $self->[_IDX_PTR] );

    return $self;
}

sub DESTROY {
    my ($self) = @_;

    $self->[ _IDX_ASCRIPT ]->{'__unpin'}->( $self->[_IDX_PTR] ) if $self->[ _IDX_PINNED ];
}

#----------------------------------------------------------------------

# Undocumented by design:
sub new {
    my ($class, $bufref, $ascript, $membase, $ptr) = @_;

    return bless [ $bufref, $ascript, $membase, $ptr ], $class;
}

1;
