
# 🚀 Progetto Workflow: Todo List Cloud-Native su AWS

Questo repository contiene il codice sorgente e l'infrastruttura come codice per "Workflow", un'applicazione web full-stack per la gestione di task, interamente costruita e deployata su Amazon Web Services.

Il progetto è stato sviluppato come dimostrazione di competenze nell'utilizzo di architetture moderne, containerizzazione e automazione DevOps in un ambiente cloud.

## ✨ Funzionalità Principali

  * **Autenticazione Sicura:** Sistema completo di registrazione e login utenti gestito tramite **AWS Cognito** e protetto da token **JWT**.
  * **Gestione Task (CRUD):** Funzionalità complete per creare, visualizzare, aggiornare ed eliminare i propri task.
  * **API Protette:** Tutti gli endpoint relativi ai dati dell'utente sono protetti e richiedono un token di autorizzazione valido.
  * **Notifiche Event-Driven:** L'architettura invia notifiche tramite **SNS** e accoda messaggi su **SQS** in risposta a eventi chiave (es. registrazione utente, completamento task), dimostrando un design asincrono e disaccoppiato.

## 🏗️ Architettura Cloud

L'infrastruttura è interamente gestita come codice tramite script AWS CLI ed è progettata per essere scalabile, sicura e resiliente.

  * **Frontend (React su S3):** L'interfaccia utente è un'applicazione single-page costruita in **React**, ospitata come sito web statico su **Amazon S3** per performance e costi contenuti.
  * **Backend (Node.js su ECS Fargate):** Il "cervello" dell'applicazione è un'API RESTful in **Node.js**, containerizzata con **Docker**. Gira in modalità serverless su **AWS ECS Fargate**, che gestisce l'orchestrazione dei container senza che io debba amministrare server. L'immagine Docker è archiviata in modo sicuro su **ECR** (Elastic Container Registry).
  * **Database (MySQL su RDS):** I dati, come utenti e task, sono salvati su un database relazionale **MySQL** gestito da **Amazon RDS**, che si occupa di backup, patch e scalabilità.
  * **Autenticazione (Cognito):** La gestione degli accessi è affidata ad **AWS Cognito**, che si occupa di tutto il ciclo di vita dell'utente in modo sicuro.
  * **Logging (CloudWatch):** Tutti i log generati dal backend vengono inviati automaticamente a **CloudWatch Logs** grazie all'integrazione nativa di ECS, permettendo un monitoraggio e un debug efficaci.
  * **Permessi (IAM):** La sicurezza tra i servizi è garantita da un **ruolo IAM** specifico per il task ECS, che concede al backend solo i permessi strettamente necessari per interagire con gli altri servizi AWS, seguendo il principio del minimo privilegio.

## 🛠️ Stack Tecnologico

| Categoria | Tecnologia |
| :--- | :--- |
| **Frontend** | React.js, Material-UI (MUI), Axios, React Router |
| **Backend** | Node.js, Express.js, JWT, Bcrypt, MySQL2 |
| **Database** | MySQL 8.0 |
| **Cloud & DevOps** | AWS (ECS, Fargate, RDS, S3, ECR, Cognito, SNS, SQS, IAM), Docker, Git, GitHub Actions (CI/CD) |

## 🚀 Deploy e Gestione

L'intero ciclo di vita dell'infrastruttura è automatizzato tramite script Bash e AWS CLI.

  * **`deploy.sh`**: Script idempotente che crea o aggiorna l'intera infrastruttura su AWS.
  * **`undeploy.sh`**: Script per un "undeploy parziale" che ferma i servizi costosi (ECS e RDS) per ridurre i costi quasi a zero, mantenendo le risorse di storage.
  * **`undeploy-total.sh`**: Script distruttivo per eliminare completamente tutte le risorse associate al progetto.

## 🔄 CI/CD - Integrazione e Deploy Continui

Il repository è configurato con un workflow di **GitHub Actions** (`.github/workflows/deploy.yml`) che automatizza il processo di rilascio.

Ogni `push` sul branch `main` innesca un processo automatico che:

1.  **Costruisce e Carica il Backend:** Crea una nuova immagine Docker del backend e la carica sul repository privato in **Amazon ECR**.
2.  **Aggiorna il Servizio:** Esegue lo script `deploy.sh` per aggiornare il servizio ECS con la nuova immagine, senza downtime.
3.  **Deploya il Frontend:** Compila l'applicazione React e sincronizza i file statici sul bucket **S3**.
