package Wasm::AssemblyScript;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Wasm::AssemblyScript - AssemblyScript conveniences in Perl

=head1 SYNOPSIS

Given a L<Wasm::Wasmtime::Instance> object:

    my $exports = $instance->exports();

    my $addrnum = $exports->{'memory'}->data();

    # $exports has several overloads; let’s get a plain hash:
    my %exports_hash = %$exports;

    my $asc = Wasm::AssemblyScript->new( $addrnum, \%exports_hash );

=head1 DESCRIPTION

L<AssemblyScript|https://www.assemblyscript.org/> defines a method
for passing strings and array buffers between the host environment
and WebAssembly. This module exposes a simple Perl implementation
of that method.

=head1 SEE ALSO

As of this writing AssemblyScript’s schema for storing strings
is documented L<here|https://www.assemblyscript.org/memory.html#internals>.

=cut

#----------------------------------------------------------------------

use Carp ();

use Wasm::AssemblyScript::Object ();

use constant {
    _ID_OFFSET => -8,
    _SIZE_OFFSET => -4,

    _ARRAYBUFFER_ID => 0,
    _STRING_ID => 1,

    # Assume that anything not 32-bit is 64-bit:
    _PTR_WIDTH_PACK => length(pack 'P') == length(pack 'L') ? 'L' : 'Q',

    _ASC_STRING_ENCODING => 'UTF-16LE',

    _U32_PTR_PACK => 'P4',
};

use constant _RUNTIME_MEMBERS => (
    '__new',
    '__pin',
    '__unpin',
    '__collect',

    # There are others (e.g., __rtti_base), but they’re undocumented
    # and unneeded.
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $MEMBASENUM [, \%EXPORTS ] )

Instantiates this class.

$MEMBASENUM is a numeric pointer to the base of the WebAssembly
instance’s memory.

%EXPORTS, if given, are the module’s exports; if you intend to allocate
memory (e.g., to pass a string to a WebAssembly function) then this
B<MUST> contain the functions from AssemblyScript’s loader API
(C<__new()> et al.), or memory allocation can’t happen.

=cut

sub new {
    my ($class, $memory_base, $exports_hr) = @_;

    return bless {
        _memory_base => $memory_base,
        $exports_hr ? ( map { ($_ => $exports_hr->{$_}) } _RUNTIME_MEMBERS ) : (),
    }, $class;
}

=head2 $str = I<OBJ>->get_text( $ADDRNUM )

Returns a text/character string stored at $ADDRNUM as a string.

(NB: This returns a B<character> string, not a byte string. If you want
to output the string, you must encode it first. See L<Encode::Simple>.)

=cut

sub get_text {
    my ($self, $ptr) = @_;

    my $asc_str = $self->_get($ptr, _STRING_ID);

    require Encode;
    return Encode::decode(_ASC_STRING_ENCODING, $asc_str, Encode::FB_CROAK());
}

=head2 $str = I<OBJ>->get_arraybuffer( $ADDRNUM )

Returns a byte string stored at $ADDRNUM as an ArrayBuffer.

=cut

sub get_arraybuffer {
    my ($self, $ptr) = @_;

    return $self->_get($ptr, _ARRAYBUFFER_ID);
}

=head2 $obj = I<OBJ>->collect()

Runs I<OBJ>’s garbage collection.

=cut

sub collect {
    $_[0]{'__collect'}->();
    return $_[0];
}

=head2 $strobj = I<OBJ>->new_text( $CHAR_STRING )

Stores $CHAR_STRING in the underlying WebAssembly object’s memory
and returns a L<Wasm::AssemblyScript::Object> instance that represents
the allocation.

(NB: This takes a B<character> string, not a byte string.)

=cut

sub new_text {
    my ($self, $str) = @_;

    require Encode;
    my $buf = Encode::encode(_ASC_STRING_ENCODING, $str);

    return $self->_alloc($buf, _STRING_ID);
}

#----------------------------------------------------------------------

sub _unpack_u32 {
    my $sysptr = shift;

    my $val = unpack( _U32_PTR_PACK, pack(_PTR_WIDTH_PACK, $sysptr) );
    return unpack 'V', $val;
}

sub _get {
    my ($self, $ptr, $expect_id) = @_;

    my $sysptr = $self->{'_memory_base'} + $ptr;

    my $id = _unpack_u32($sysptr + _ID_OFFSET);

    if ($id != $expect_id) {
        Carp::confess(sprintf "WASM object at memory address $ptr has ID $id; expected %d.", $expect_id);
    }

    my $size = _unpack_u32($sysptr + _SIZE_OFFSET);

    return unpack( "P$size", pack(_PTR_WIDTH_PACK, $sysptr) );
}

sub _memcpy {
    my ($addrnum, $buf) = @_;

    require IPC::SysV;
    IPC::SysV::memwrite(
        pack( _PTR_WIDTH_PACK, $addrnum ),
        $buf,
        0,
        length $buf,
    );
}

sub _alloc {
    my ($self, $buf, $id) = @_;

    if (!$self->{'__new'}) {
        Carp::confess "No “__new” function in WASM exports; did you forget asc’s “--exportRuntime” argument?";
    }

    my $ptr = $self->{'__new'}->(length $buf, $id);

    _memcpy($ptr + $self->{'_memory_base'}, $buf);

    return Wasm::AssemblyScript::Object->new( $self, $self->{'_memory_base'}, $ptr );
}


1;
