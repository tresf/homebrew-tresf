class OpenjdkAT16 < Formula
  # This isn't openjdk@16, but rather openjdk@16 with the JEP-391 patches from sandbox repo
  # as a stop-gap solution for Apple Silicon
  desc "Development kit for the Java programming language"
  homepage "https://openjdk.java.net/"
  url "https://github.com/openjdk/jdk-sandbox/archive/a56ddad05cf1808342aeff1b1cd2b0568a6cdc3a.tar.gz"
  version "16"
  sha256 "29df31b5eefb5a6c016f50b2518ca29e8e61e3cfc676ed403214e1f13a78efd5"
  license :cannot_represent

  bottle do
    cellar :any
    sha256 "6f31366f86a5eacf66673fca9ad647b98b207820f8cfea49a22af596395d3dba" => :big_sur
    sha256 "9376a1c6fdf8b0268b6cb56c9878358df148b530fcb0e3697596155fad3ca8d7" => :catalina
    sha256 "a4f00dc8b4c69bff53828f32c82b0a6be41b23a69a7775a95cdbc9e01d9bdb68" => :mojave
    sha256 "bef2e4a43a6485253c655979cfc719332fb8631792720c0b9f6591559fb513f1" => :high_sierra
  end

  keg_only "it shadows the macOS `java` wrapper"

  depends_on "autoconf" => :build

  on_linux do
    depends_on "pkg-config" => :build
    depends_on "alsa-lib"
  end

  # From https://jdk.java.net/archive/
  resource "boot-jdk" do
    on_macos do
      url "https://download.java.net/java/early_access/jdk16/25/GPL/openjdk-16-ea+25_osx-x64_bin.tar.gz"
      sha256 "e08a359771834d0f298f9b08672328758985743d0feefdf4b705a2d6218fecff"
    end
    on_linux do
      url "https://download.java.net/java/early_access/jdk16/26/GPL/openjdk-16-ea+26_linux-x64_bin.tar.gz"
      sha256 "e74300f3f770122358d768d45e181d29c710e8d41bbc4ab8e492929f2867347c"
    end
  end

  # Calculate Xcode's dual-arch JavaNativeFoundation.framework path
  def framework_path
    File.expand_path("../SharedFrameworks/ContentDeliveryServices.framework/Versions/Current/itms/java/Frameworks",
      MacOS::Xcode.prefix)
  end

  def install
    boot_jdk_dir = Pathname.pwd/"boot-jdk"
    resource("boot-jdk").stage boot_jdk_dir
    boot_jdk = boot_jdk_dir/"Contents/Home"

    java_options = ENV.delete("_JAVA_OPTIONS")

    # Inspecting .hgtags to find a build number
    # The file looks like this:
    #
    # 23fd169be90a803fef99776afefa3072189980be jdk-15.0.1+7
    # 8dd4d8eaf0de32a79d1f48c3421e5666d75beff9 jdk-15.0.1+8
    #
    build = File.read(".hgtags")
                .scan(/ jdk-#{version}\+(.+)$/)
                .map(&:first)
                .map(&:to_i)
                .max
    raise "cannot find build number in .hgtags" if build.nil?

    configure_args = %W[
      --without-version-pre
      --without-version-opt
      --with-version-build=#{build}
      --with-toolchain-path=/usr/bin
      --with-sysroot=#{MacOS.sdk_path}
      --with-extra-ldflags=-headerpad_max_install_names
      --with-boot-jdk=#{boot_jdk}
      --with-boot-jdk-jvmargs=#{java_options}
      --with-build-jdk=#{boot_jdk}
      --with-debug-level=release
      --with-native-debug-symbols=none
      --enable-dtrace
      --with-jvm-variants=server
    ]
    on_macos do
      if Hardware::CPU.arm?
        configure_args += %W[
          --disable-warnings-as-errors
          --openjdk-target=aarch64-apple-darwin
          --with-extra-cflags=-arch\ arm64
          --with-extra-ldflags=-arch\ arm64\ -F#{framework_path}
          --with-extra-cxxflags=-arch\ arm64
        ]
      end
    end

    chmod 0755, "configure"
    system "./configure", *configure_args

    ENV["MAKEFLAGS"] = "JOBS=#{ENV.make_jobs}"
    system "make", "images"

    jdk = Dir["build/*/images/jdk-bundle/*"].first
    libexec.install jdk => "openjdk.jdk"
    bin.install_symlink Dir["#{libexec}/openjdk.jdk/Contents/Home/bin/*"]
    include.install_symlink Dir["#{libexec}/openjdk.jdk/Contents/Home/include/*.h"]
    include.install_symlink Dir["#{libexec}/openjdk.jdk/Contents/Home/include/darwin/*.h"]
  end

  def post_install
    on_macos do
      # Copy JavaNativeFoundation.framework from Xcode after install to avoid signature corruption
      if Hardware::CPU.arm?
        cp_r "#{framework_path}/JavaNativeFoundation.framework",
          "#{libexec}/openjdk.jdk/Contents/Home/lib/JavaNativeFoundation.framework",
          remove_destination: true
      end
    end
  end

  def caveats
    <<~EOS
      For the system Java wrappers to find this JDK, symlink it with
        sudo ln -sfn #{opt_libexec}/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
    EOS
  end

  test do
    (testpath/"HelloWorld.java").write <<~EOS
      class HelloWorld {
        public static void main(String args[]) {
          System.out.println("Hello, world!");
        }
      }
    EOS

    system bin/"javac", "HelloWorld.java"

    assert_match "Hello, world!", shell_output("#{bin}/java HelloWorld")
  end
end
