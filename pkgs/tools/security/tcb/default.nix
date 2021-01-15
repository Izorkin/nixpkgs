{ lib, stdenv, fetchurl, linux-pam, libxcrypt }:

stdenv.mkDerivation rec {
  pname = "tcb";
  version = "1.2";

  src = fetchurl {
    url = "https://www.openwall.com/${pname}/${pname}-${version}.tar.gz";
    sha256 = "1m0b4m5495lw82y86hy5waj81bq20agz99p56qqjgzasp1ya3cak";
  };

  buildInputs = [ linux-pam libxcrypt ];

  patches = [ ./fix-install.patch ];

  postPatch = ''
    substituteInPlace libs/Makefile \
      --replace '$(DESTDIR)' $out
    substituteInPlace misc/Makefile \
      --replace '$(DESTDIR)' $out
    substituteInPlace pam_tcb/Makefile \
       --replace '$(DESTDIR)' $out
    substituteInPlace progs/Makefile \
      --replace '$(DESTDIR)$(LIBEXECDIR)' $out/libexec \
      --replace '$(DESTDIR)' $out
  '';

  meta = with lib; {
    description = ''
      The tcb package contains core components of our tcb suite implementing the alternative
      password shadowing scheme on Openwall GNU Linux (Owl).
    '';
    longDescription = ''
      The tcb package contains core components of our tcb suite implementing the alternative
      password shadowing scheme on Openwall GNU Linux (Owl). It is being made available
      separately from Owl primarily for use by other distributions.

      The package consists of three components: pam_tcb, libnss_tcb, and libtcb.

      pam_tcb is a PAM module which supersedes pam_unix. It also implements the tcb password
      shadowing scheme. The tcb scheme allows many core system utilities (passwd(1) being
      the primary example) to operate with little privilege. libnss_tcb is the accompanying
      NSS module. libtcb contains code shared by the PAM and NSS modules and is also used
      by user management tools on Owl due to our shadow suite patches.
    '';
    homepage    = "https://www.openwall.com/tcb/";
    license     = licenses.bsd3;
    platforms   = platforms.unix;
    maintainers = with maintainers; [ izorkin ];
  };
}
