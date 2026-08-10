# Third-party test data

## `charLSMonochrome2x2`

Source: [`team-charls/charls`](https://github.com/team-charls/charls),
`test/data/8bit-monochrome-2x2.jls`.

The 29-byte JPEG-LS interchange stream is retained in
`Support/JPEGLSTestSupport.swift` as a byte array and decodes to the 8-bit
monochrome samples `1, 2, 3, 4`. CharLS declares binary `.jls` test data as
BSD-3-Clause in its [`REUSE.toml`](https://github.com/team-charls/charls/blob/main/REUSE.toml).

- Source commit: `c0bae6496fa5d787fbb4698debd1e5decb40cf3a`
- SHA-256: `7377a5fc8fe8dc4958dc87312e7458df04aa96b804c5021bd5352b049cca5481`
- Source license: <https://github.com/team-charls/charls/blob/main/LICENSE.md>

Copyright (c) 2024 Team CharLS

BSD 3-Clause License

Copyright (c) 2007, Jan de Vaan and Victor Derks

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## `charLS12BitMonochrome2x2`

This 35-byte JPEG-LS stream was generated using the source-pinned CharLS
encoder noted above, with a 2 × 2, single-component, 12-bit input containing
the little-endian samples `1, 2, 4095, 1024`. It is retained as a byte array
in `Support/JPEGLSTestSupport.swift` so the test suite has a compact,
independent encoder-derived 16-bit DICOM storage vector.

- Generator source commit: `c0bae6496fa5d787fbb4698debd1e5decb40cf3a`
- SHA-256: `1e874c8127b683bc13949b3160a500e5a8a6aa6c099a178276ac0d8412069e1a`
- License: BSD-3-Clause, reproduced in the preceding notice

## `charLSCustomParametersMonochrome2x2`

This 44-byte JPEG-LS stream was generated using the source-pinned CharLS
encoder, with 8-bit samples `1, 2, 3, 4` and explicit Preset Coding
Parameters `MAXVAL=255`, `T1=4`, `T2=8`, `T3=22`, and `RESET=64`.

- Generator source commit: `c0bae6496fa5d787fbb4698debd1e5decb40cf3a`
- SHA-256: `4f82d4fbb6931a79b530c42fe9e1de2ea25f1a44c1ee9442f1d4604f1268008c`
- License: BSD-3-Clause, reproduced above

## `charLSRestartMonochrome1x2`, `charLSRGBSampleInterleaved1x1`, and `charLSNearLosslessMonochrome2x2`

These compact JPEG-LS streams were generated with the source-pinned CharLS
encoder noted above. They respectively exercise a restart interval, a
sample-interleaved 8-bit RGB frame (`10, 20, 30`), and Near-Lossless coding
with `NEAR = 1` (`10, 20, 30, 40`). They are retained as byte arrays in
`Support/JPEGLSTestSupport.swift`.

- Generator source commit: `c0bae6496fa5d787fbb4698debd1e5decb40cf3a`
- License: BSD-3-Clause, reproduced above

## `CT_small.dcm`

Source: [`pydicom/pydicom`](https://github.com/pydicom/pydicom),
`src/pydicom/data/test_files/CT_small.dcm`.

The source project distributes this fixture under the MIT License. Its test-data
documentation describes it as a downsized, anonymized 128 × 128 CT image using
Explicit VR Little Endian transfer syntax. The original source and license are
preserved here for attribution and reproducibility:

- Source commit: `0e98c4aeecce7c3ae537e3fbe9133d3fbc005796`
- SHA-256: `3dd31e5cc835b3f2cdd46c9da1982f59251e78518fefa8163d914631c66437d6`
- Source license: <https://github.com/pydicom/pydicom/blob/main/LICENSE>
- Test-data notes: <https://github.com/pydicom/pydicom/blob/main/src/pydicom/data/test_files/README.txt>

Copyright (c) 2008-2020 Darcy Mason and pydicom contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
