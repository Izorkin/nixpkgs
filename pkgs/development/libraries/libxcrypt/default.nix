{ lib, stdenv, fetchFromGitHub
, autoconf, automake, libtool, pkgconfig
}:

stdenv.mkDerivation rec {
  pname = "libxcrypt";
  version = "4.4.17";

  src = fetchFromGitHub {
    owner = "besser82";
    repo = pname;
    rev = "v${version}";
    sha256 = "0rm6zrd5pvmv684yy0ajryzwc3haljgr8b4mkj387r0aqhj4hyiq";
  };

  nativeBuildInputs = [ autoconf automake libtool pkgconfig ];

  preConfigure = ''
    ./autogen.sh
  '';

  meta = with lib; {
    description = "libxcrypt is a modern library for one-way hashing of passwords.";
    longDescription = ''
      libxcrypt is a modern library for one-way hashing of passwords. It supports a wide
      variety of both modern and historical hashing methods: yescrypt, gost-yescrypt,
      scrypt, bcrypt, sha512crypt, sha256crypt, md5crypt, SunMD5, sha1crypt, NT, bsdicrypt,
      bigcrypt, and descrypt. It provides the traditional Unix crypt and crypt_r interfaces,
      as well as a set of extended interfaces pioneered by Openwall Linux, crypt_rn, crypt_ra,
      crypt_gensalt, crypt_gensalt_rn, and crypt_gensalt_ra.
    '';
    homepage    = "https://github.com/besser82/libxcrypt/";
    license     = licenses.lgpl21Only;
    platforms   = platforms.unix;
    maintainers = with maintainers; [ izorkin ];
  };
}
