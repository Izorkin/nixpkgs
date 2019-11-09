{ stdenv, fetchFromGitHub, autoreconfHook, pkgconfig
, cunit, file
, jemalloc, libev, nghttp3, wolfssl
}:

stdenv.mkDerivation rec {
  pname = "ngtcp2";
  version = "2019.12.08";

  src = fetchFromGitHub {
    owner = "${pname}";
    repo = "${pname}";
    rev = "4c75c29cbf433dc2fcafdf2ca2f05370e462c405";
    sha256 = "1i2vmc3fq1rhigl3igr0abqxvzdfyakpk4i9hl1bvyb51j5zla5r";
  };

  nativeBuildInputs = [ autoreconfHook pkgconfig cunit file ];
  buildInputs = [ jemalloc libev nghttp3 wolfssl ];

  preConfigure = ''
    substituteInPlace ./configure --replace /usr/bin/file ${file}/bin/file
  '';

  doCheck = true;

  meta = with stdenv.lib; {
    homepage = "https://github.com/ngtcp2/ngtcp2";
    description = "ngtcp2 project is an effort to implement QUIC protocol which is now being discussed in IETF QUICWG for its standardization.";
    license = licenses.mit;
    platforms = platforms.all;
  };
}

