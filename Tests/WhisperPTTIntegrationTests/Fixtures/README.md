# Speech fixtures

Generated locally with macOS speech synthesis, as mono 16 kHz PCM WAV files.

```sh
say -v Tingting -r 155 --data-format=LEI16@16000 -o zh.wav '你好，今天我们测试语音识别，请保留我说话时使用的语言，不要翻译成英语。'
say -v Samantha -r 155 --data-format=LEI16@16000 -o en.wav 'Hello, today we are testing speech recognition. Please keep the language I speak and do not translate it into another language.'
```

These original phrases test language preservation, rather than exact spelling or punctuation.
