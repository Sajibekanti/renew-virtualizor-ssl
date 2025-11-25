# Virtualizor SSL Auto Renew Script

A simple Bash script to automatically **renew**, **install**, and **activate** SSL for **Virtualizor (EMPS Web Server)** using **acme.sh**.

---

## 📌 Requirements

* Root access
* `acme.sh` installed
* `socat` installed (script installs it automatically)

---

## 📥 Installation

### 1. Upload script to server

Save the script as:

```
/usr/local/sbin/renew_virtualizor_ssl.sh
```

### 2. Make script executable

```bash
chmod +x /usr/local/sbin/renew_virtualizor_ssl.sh
```

---

## 🚀 Usage

Run the script with domain and email:

```bash
sudo /usr/local/sbin/renew_virtualizor_ssl.sh <domain> <email>
```

Example:

```bash
sudo /usr/local/sbin/renew_virtualizor_ssl.sh server4.bdixnode.com support@bdixnode.com
```

If you run it without arguments:

```bash
sudo /usr/local/sbin/renew_virtualizor_ssl.sh
```

It will default to:

```
domain = server4.bdixnode.com
email  = support@bdixnode.com
```

---

## 🔄 What the Script Does

* Stops & masks Virtualizor (freeing port 80)

* Issues/renews SSL via acme.sh standalone

* Installs new cert into:

  ```
  /usr/local/virtualizor/conf/virtualizor.crt
  /usr/local/virtualizor/conf/virtualizor.key
  ```

* Restarts Virtualizor to activate SSL

* Verifies certificate

* Logs everything in:

  ```
  /var/log/renew_virtualizor_ssl_<domain>.log
  ```

---

## ⏲ Optional: Auto-Renew via Cron

Edit crontab:

```bash
crontab -e
```

Add:

```
15 3 * * 1 /usr/local/sbin/renew_virtualizor_ssl.sh server4.bdixnode.com support@bdixnode.com >> /var/log/virt_ssl_cron.log 2>&1
```

This runs every Monday at 3:15 AM.

---

## 🧪 Verify SSL Manually

```bash
openssl s_client -connect server4.bdixnode.com:443 -servername server4.bdixnode.com </dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

---
