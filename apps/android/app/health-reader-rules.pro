# Pinned fastexcel 0.20.2 adapter for an authenticated SeekableByteChannel.
-keep class org.dhatim.fastexcel.reader.OPCPackage {
    <init>(org.apache.commons.compress.archivers.zip.ZipFile, boolean);
}
-keepclassmembers class org.dhatim.fastexcel.reader.ReadableWorkbook {
    <init>(org.dhatim.fastexcel.reader.OPCPackage, org.dhatim.fastexcel.reader.ReadingOptions);
}
