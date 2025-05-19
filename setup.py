import os
from setuptools import setup, Extension
from setuptools.command.build_ext import build_ext
import shutil

zentencepiece = Extension("zentencepiece", sources=["zentencepiecemodule.zig"])


class ZigBuilder(build_ext):
    def build_extension(self, ext):
        assert len(ext.sources) == 1

        if not os.path.exists(self.build_lib):
            os.makedirs(self.build_lib)

        output_path = self.get_ext_fullpath(ext.name)

        self.spawn(
            [
                "zig",
                "build",
                "python",
                "-Doptimize=ReleaseFast",
                f"-Dinclude_dirs={','.join(self.include_dirs)}"
            ]
        )

        shutil.copy(f"zig-out/lib/libzentencepiece.so", output_path)


setup(
    name="zentencepiece",
    version="0.0.1",
    description="Experimental sentencepiece tokenizer written purely in Zig",
    ext_modules=[zentencepiece],
    cmdclass={"build_ext": ZigBuilder},
)