---
title: 记一次调用HTTPS接口证书问题排查
date: 2020-06-30 17:59:35
tags: [https]
---



## 问题

发现系统调用HTTPS接口时出现异常，异常信息如下

```
javax.net.ssl.SSLHandshakeException: sun.security.validator.ValidatorException: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
```



## 排查

怀疑1：接口提供方的证书过期了？（其实仔细看日志的话就可以排除这个可能）

操作：  通过本地浏览器打开对应url，浏览器显示正常的安全信息，样例如下，这时可以排除证书问题

<img src="/images/certificate.png" style="zoom:60%" />



怀疑2:  接口换了证书，服务器没有对应的根证书？

操作： 通过浏览器访问，查询到接口提供方对应的根证书为：`DST Root CA X3`

上网查询到 [获取服务器（linux）所有根证书的命令](https://unix.stackexchange.com/questions/97244/list-all-available-ssl-ca-certificates/97249#97249) 如下

`awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-bundle.crt`

在服务器执行后，可以在其中找到对应的一行信息，根证书`subject= /O=Digital Signature Trust Co./CN=DST Root CA X3`，这时又可以证明服务器是有对应的根证书的，排除此可能



其实这时候有点没有头绪了，不知道如何继续，直到后来发现 JVM 读取的是它自己的证书而不是服务器的...



怀疑3：JVM的受信证书中没有对应的根证书？

操作：  查询对应 jvm 默认的受信根证书列表

`keytool -keystore "$JAVA_HOME/jre/lib/security/cacerts" -storepass changeit -list -v`

在其结果中查询无 `DST Root CA X3` 证书相关信息！

至此找到了问题的原因，不过也挺奇怪的，服务器和我本地安装的都是 jdk1.8，但是我本地 jvm 中是有这个根证书的



## 解决

1. 使用keytool工具将导出的证书导入到jvm的受信证书中去，详细操作在[stackoverflow](https://stackoverflow.com/questions/21076179/pkix-path-building-failed-and-unable-to-find-valid-certification-path-to-requ)

2. 在Java代码中设置 [信任任何证书](https://stackoverflow.com/questions/2642777/trusting-all-certificates-using-httpclient-over-https/6378872#6378872)（不安全）

```java
private void trustEveryone() { 
    try { 
        HttpsURLConnection.setDefaultHostnameVerifier(new HostnameVerifier(){ 
                public boolean verify(String hostname, SSLSession session) { 
                        return true; 
                }}); 
        SSLContext context = SSLContext.getInstance("TLS"); 
        context.init(null, new X509TrustManager[]{new X509TrustManager(){ 
                public void checkClientTrusted(X509Certificate[] chain, 
                                String authType) throws CertificateException {} 
                public void checkServerTrusted(X509Certificate[] chain, 
                                String authType) throws CertificateException {} 
                public X509Certificate[] getAcceptedIssuers() { 
                        return new X509Certificate[0]; 
                }}}, new SecureRandom()); 
        HttpsURLConnection.setDefaultSSLSocketFactory(context.getSocketFactory()); 
    } catch (Exception e) { // should never happen 
        e.printStackTrace(); 
    } 
} 
```



以上为排查的具体过程，如果有错误，欢迎大家告知补充，谢谢

