=begin
Notes from https://gist.github.com/claui/ea4248aa64d6a1b06c6d6ed80bc2d2b8#gistcomment-3535821

if you want to build our jep-391 preview branch then use these configure arguments (assuming it's done on intel mac with Xcode12):

sh configure
[x] --with-boot-jdk=/path/to/some/jdk15_or16ea/for/intel
[x] --with-build-jdk=/path/to/openjdk16ea/build/for/intel
[x] --with-debug-level=release
[x] --disable-warnings-as-errors
[x] --openjdk-target=aarch64-apple-darwin
[x] --with-extra-cflags='-arch arm64'
[x] --with-extra-ldflags='-arch arm64 -F/path/to/Xcode.app//Contents/SharedFrameworks/ContentDeliveryServices.framework/Versions/A/itms/java/Frameworks/'
[x] --with-extra-cxxflags='-arch arm64'

make images

then copy JavaNativeFoundation.framework to $JAVA_HOME/lib/

p.s. build-jdk better be exact same version as the one you trying to build
=end

class Openjdk < Formula
  desc "Development kit for the Java programming language"
  homepage "https://openjdk.java.net/"
  url "https://github.com/openjdk/jdk-sandbox/archive/a56ddad05cf1808342aeff1b1cd2b0568a6cdc3a.tar.gz"
  version "16.0.0+10ea"
  sha256 "9c5be662f5b166b5c82c27de29b71f867cff3ff4570f4c8fa646490c4529135a"
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
      url "https://download.java.net/java/GA/jdk14.0.2/205943a0976c4ed48cb16f1043c5c647/12/GPL/openjdk-14.0.2_linux-x64_bin.tar.gz"
      sha256 "91310200f072045dc6cef2c8c23e7e6387b37c46e9de49623ce0fa461a24623d"
    end
  end

  def install
    boot_jdk_dir = Pathname.pwd/"boot-jdk"
    resource("boot-jdk").stage boot_jdk_dir
    boot_jdk = boot_jdk_dir/"Contents/Home"
    java_options = ENV.delete("_JAVA_OPTIONS")
    framework = "/Applications/Xcode.app/Contents/SharedFrameworks/ContentDeliveryServices.framework/Versions/A/itms/java/Frameworks/JavaNativeFoundation.framework"

    # Inspecting .hg_archival.txt to find a build number
    # The file looks like this:
    #
    # repo: fd16c54261b32be1aaedd863b7e856801b7f8543
    # node: e3f940bd3c8fcdf4ca704c6eb1ac745d155859d5
    # branch: default
    # tag: jdk-15+36
    # tag: jdk-15-ga
    #
    # Since openjdk has move their development from mercurial to git and GitHub
    # this approach may need some changes in the future
    #
    build = File.read(".hg_archival.txt")
                .scan(/^tag: jdk-#{version}\+(.+)$/)
                .map(&:first)
                .map(&:to_i)
                .max
    raise "cannot find build number in .hg_archival.txt" if build.nil?

    chmod 0755, "configure"
    system "./configure", "--without-version-pre",
                          "--without-version-opt",
                          "--with-version-build=#{build}",
                          "--with-toolchain-path=/usr/bin",
                          "--with-sysroot=#{MacOS.sdk_path}",
                          "--with-extra-ldflags=-headerpad_max_install_names",
                          "--with-boot-jdk=#{boot_jdk}",
                          "--with-boot-jdk-jvmargs=#{java_options}",
                          "--with-build-jdk=#{boot_jdk}",
                          "--with-debug-level=release",
                          "--with-native-debug-symbols=none",
                          "--enable-dtrace",
                          "--with-jvm-variants=server",
                          "--disable-warnings-as-errors",
                          "--openjdk-target=aarch64-apple-darwin",
                          "--with-extra-cflags='-arch arm64'",
                          "--with-extra-ldflags='-arch arm64 -F#{framework}'",
                          "--with-extra-cxxflags='-arch arm64'"

    ENV["MAKEFLAGS"] = "JOBS=#{ENV.make_jobs}"
    system "make", "images"

    jdk = Dir["build/*/images/jdk-bundle/*"].first
    libexec.install jdk => "openjdk.jdk"
    bin.install_symlink Dir["#{libexec}/openjdk.jdk/Contents/Home/bin/*"]
    include.install_symlink Dir["#{libexec}/openjdk.jdk/Contents/Home/include/*.h"]
    include.install_symlink Dir["#{libexec}/openjdk.jdk/Contents/Home/include/darwin/*.h"]
    
    FileUtils.copy_entry "#{framework}", "#{libexec}/openjdk.jdk/Contents/Home/lib/"
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
