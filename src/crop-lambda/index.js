// src/crop-lambda/index.js
const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");

const s3 = new S3Client();

exports.handler = async (event) => {
  
    for (const record of event.Records) {
        // SQS envuelve el mensaje de S3 en un texto, lo desempaquetamos:
        const sqsBody = JSON.parse(record.body);
        
        for (const s3Event of sqsBody.Records || []) {
            const bucket = s3Event.s3.bucket.name;
            const key = decodeURIComponent(s3Event.s3.object.key.replace(/\+/g, ' '));

            try {
                // 1. Descargamos la imagen original de la carpeta uploads/
                const getReq = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
                const chunks = [];
                for await (const chunk of getReq.Body) chunks.push(chunk);
                const imageBuffer = Buffer.concat(chunks);

                // 2. Recortamos con Sharp (40x40 y máscara circular)
                const circleSvg = Buffer.from('<svg><circle cx="20" cy="20" r="20" /></svg>');
                
                const processedBuffer = await sharp(imageBuffer)
                    .resize(40, 40, { fit: 'cover' })
                    .composite([{ input: circleSvg, blend: 'dest-in' }])
                    .png()
                    .toBuffer();

                const newKey = key
                    .replace(process.env.UPLOAD_PREFIX, process.env.PROCESSED_PREFIX)
                    .replace(/\.[^/.]+$/, "") + "_circular.png";

                await s3.send(new PutObjectCommand({
                    Bucket: process.env.S3_BUCKET,
                    Key: newKey,
                    Body: processedBuffer,
                    ContentType: "image/png"
                }));

                console.log(`Imagen procesada y guardada en: ${newKey}`);

            } catch (error) {
                console.error("Error procesando imagen:", error);
                throw error; // Esto hace que el mensaje falle y vaya a la DLQ si falla 3 veces
            }
        }
    }
    return "Procesamiento completado";
};
