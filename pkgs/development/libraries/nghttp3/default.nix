{ stdenv, fetchFromGitHub, autoreconfHook, pkgconfig
, cunit, file
}:

stdenv.mkDerivation rec {
  pname = "nghttp3";
  version = "2019.12.08";

  src = fetchFromGitHub {
    owner = "ngtcp2";
    repo = "${pname}";
    rev = "6cc65650885f91f90f19301956de16ecc3aa8b46";
    sha256 = "13z6cm4pnaq3yap5bcvi2xfwp24syk5apwaqp0m6ixx3zhg6ndff";
  };

  nativeBuildInputs = [ autoreconfHook pkgconfig cunit file ];

  preConfigure = ''
    substituteInPlace ./configure --replace /usr/bin/file ${file}/bin/file
  '';

  doCheck = true;

  meta = with stdenv.lib; {
    homepage = "https://github.com/ngtcp2/nghttp3";
    description = "nghttp3 is an implementation of HTTP/3 mapping over QUIC and QPACK in C.";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
